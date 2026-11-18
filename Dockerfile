ARG BASE_IMAGE="amazoncorretto:21.0.13-al2023"

FROM $BASE_IMAGE AS overlay

ARG EXT_BUILD_COMMANDS=""
ARG EXT_BUILD_OPTIONS=""

WORKDIR /cas-overlay
COPY ./src src/
COPY ./gradle/ gradle/
COPY ./gradlew ./settings.gradle ./build.gradle ./gradle.properties ./lombok.config ./*.lockfile ./

# gradlew needs xargs, which the AL2023 Corretto image omits
RUN dnf install -y findutils && dnf clean all \
    && mkdir -p ~/.gradle \
    && echo "org.gradle.daemon=false" >> ~/.gradle/gradle.properties \
    && echo "org.gradle.configureondemand=true" >> ~/.gradle/gradle.properties \
    && chmod 750 ./gradlew \
    && ./gradlew --version;

RUN ./gradlew clean build $EXT_BUILD_COMMANDS --parallel --no-daemon -Pexecutable=false $EXT_BUILD_OPTIONS;

RUN java -Djarmode=tools -jar build/libs/cas.war extract \
    && java -XX:ArchiveClassesAtExit=./cas/cas.jsa -Dspring.context.exit=onRefresh -jar cas/cas.war

FROM $BASE_IMAGE AS cas

RUN mkdir -p /etc/cas/config \
    && mkdir -p /etc/cas/services \
    && mkdir -p /etc/cas/saml;

WORKDIR cas-overlay
COPY --from=overlay /cas-overlay/cas cas/

COPY etc/cas/ /etc/cas/

EXPOSE 8080 8443

# Declared late so per-build values do not invalidate the layer cache above
ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.title="LibreOne CAS" \
      org.opencontainers.image.description="LibreTexts single sign-on server, built on Apereo CAS" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.vendor="LibreTexts" \
      org.opencontainers.image.documentation="https://github.com/LibreTexts/LibreOne-CAS-7/blob/master/README.md" \
      org.opencontainers.image.source="https://github.com/LibreTexts/LibreOne-CAS-7" \
      org.opencontainers.image.licenses="Apache-2.0"

ENV PATH $PATH:$JAVA_HOME/bin:.

ENTRYPOINT ["java", "-server", "-noverify", "-Xmx6144M", "-XX:SharedArchiveFile=cas/cas.jsa", "-jar", "cas/cas.war"]
