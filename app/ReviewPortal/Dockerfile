ARG RUNTIME_IMAGE
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG NUGET_SOURCE=https://api.nuget.org/v3/index.json
WORKDIR /src
COPY ReviewPortal.csproj packages.lock.json ./
COPY . .
RUN dotnet restore --locked-mode --source "${NUGET_SOURCE}"
RUN dotnet publish --no-restore -c Release -o /out /p:UseAppHost=false

# Supply an organization-approved .NET 10 image and immutable digest.
# This SSL profile requires the verified Azure Linux 3 vendor configuration layout.
FROM ${RUNTIME_IMAGE} AS runtime
WORKDIR /app
COPY --from=build /out .
COPY openssl-tls.cnf /app/openssl-tls.cnf
RUN chmod -R a+rX /app && chmod 0444 /app/openssl-tls.cnf
USER 1654:1654
RUN test -r /etc/pki/tls/openssl.cnf && test -s /etc/pki/tls/openssl.cnf \
    && test -r /etc/pki/tls/symcrypt_prov.cnf && test -s /etc/pki/tls/symcrypt_prov.cnf \
    && grep -Eq '^[[:space:]]*openssl_conf[[:space:]]*=[[:space:]]*openssl_init[[:space:]]*(#.*)?$' /etc/pki/tls/openssl.cnf \
    && grep -Eq '^[[:space:]]*\[[[:space:]]*openssl_init[[:space:]]*\]' /etc/pki/tls/openssl.cnf
EXPOSE 8080
ENV ASPNETCORE_HTTP_PORTS=8080
ENV OPENSSL_CONF=/app/openssl-tls.cnf
ENTRYPOINT ["dotnet", "ReviewPortal.dll"]
