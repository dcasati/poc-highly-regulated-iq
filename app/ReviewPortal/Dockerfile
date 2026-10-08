ARG RUNTIME_IMAGE
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG NUGET_SOURCE=https://api.nuget.org/v3/index.json
WORKDIR /src
COPY ReviewPortal.csproj packages.lock.json ./
COPY . .
RUN dotnet restore --locked-mode --source "${NUGET_SOURCE}"
RUN dotnet publish --no-restore -c Release -o /out /p:UseAppHost=false

# Supply an organization-approved .NET 10 image and immutable digest.
FROM ${RUNTIME_IMAGE} AS runtime
WORKDIR /app
COPY --from=build /out .
USER 1654:1654
EXPOSE 8080
ENV ASPNETCORE_HTTP_PORTS=8080
ENTRYPOINT ["dotnet", "ReviewPortal.dll"]
