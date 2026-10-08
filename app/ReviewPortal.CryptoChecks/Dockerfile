ARG SDK_IMAGE
ARG APP_IMAGE
FROM ${SDK_IMAGE} AS build
ARG SDK_IMAGE
ARG APP_IMAGE
WORKDIR /src
RUN set -eu; \
    for image in "$SDK_IMAGE" "$APP_IMAGE"; do \
      case "$image" in *@sha256:*) ;; *) echo "Immutable SDK_IMAGE and APP_IMAGE are required." >&2; exit 1 ;; esac; \
      digest="${image##*@sha256:}"; \
      printf '%s' "$digest" | grep -Eq '^[0-9a-f]{64}$' || exit 1; \
    done
COPY ReviewPortal.CryptoChecks.csproj packages.lock.json NuGet.Config ./
RUN dotnet restore ReviewPortal.CryptoChecks.csproj --locked-mode \
    --configfile /src/NuGet.Config --packages /offline-cache -p:NuGetAudit=false
COPY Evidence.cs EncryptionChecks.cs Options.cs NativeCrypto.cs Probes.cs Program.cs ./
RUN dotnet publish ReviewPortal.CryptoChecks.csproj --no-restore -c Release \
    --self-contained false -p:UseAppHost=false -o /out \
    && chmod -R a-w /out

# Inherit the exact portal image's USER, WORKDIR, environment and entrypoint.
# The only filesystem addition is the isolated, root-owned, read-only diagnostic output.
FROM ${APP_IMAGE} AS qualification
COPY --from=build --chown=0:0 /out/ /opt/review-portal-crypto-checks/
RUN set -eu; \
    test "$(id -u)" = 1654; \
    test ! -w /opt/review-portal-crypto-checks; \
    test ! -w /opt/review-portal-crypto-checks/ReviewPortal.CryptoChecks.dll; \
    status=0; \
    if command -v timeout >/dev/null 2>&1; then \
      DOTNET_EnableDiagnostics=0 timeout -k 5s 60s dotnet \
        /opt/review-portal-crypto-checks/ReviewPortal.CryptoChecks.dll --timeout-seconds 45 || status=$?; \
    else \
      echo "External timeout unavailable; using diagnostic's 45-second process deadline."; \
      DOTNET_EnableDiagnostics=0 dotnet \
        /opt/review-portal-crypto-checks/ReviewPortal.CryptoChecks.dll --timeout-seconds 45 || status=$?; \
    fi; \
    case "$status" in \
      2) echo "CRYPTO_OBSERVATION_EXIT=2 QUALIFIED=false; observations completed, NOT certification." ;; \
      *) echo "CRYPTO_OBSERVATION_OPERATIONAL_FAILURE exit=$status" >&2; exit 1 ;; \
    esac
