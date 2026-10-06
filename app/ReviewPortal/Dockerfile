ARG RUNTIME_IMAGE
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY ReviewPortal.csproj packages.lock.json ./
RUN dotnet restore --locked-mode
COPY . .
RUN dotnet publish --no-restore -c Release -o /out /p:UseAppHost=false

# Supply an organization-approved .NET 10 image and immutable digest.
FROM ${RUNTIME_IMAGE} AS runtime
WORKDIR /app
COPY --from=build /out .
USER 1654:1654
EXPOSE 8080
ENV ASPNETCORE_HTTP_PORTS=8080
ENTRYPOINT ["dotnet", "ReviewPortal.dll"]
