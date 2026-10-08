# Linux crypto observation harness

This separate .NET 10 console is **not the portal**, an approval gate, a cryptographic
module, a compliance workaround or a FIPS certification. It uses synthetic inputs
only. It never processes a Form3500 document or makes an eligibility/review decision.
No production project, image, provider configuration or cryptographic default is
changed. It has no package dependencies; tests use the existing test-package versions.

The current requirement is **FIPS 140-3 encryption evidence**. Hash, signature and
RNG results remain supplemental observations, not independent whole-application
certification prerequisites. None of these results can validate a certificate,
authorize an operating environment or waive the encryption evidence gate.

## Build and local validation

From the authoritative repository root, using its already-populated package cache:

```sh
dotnet restore app/ReviewPortal.CryptoChecks.Tests/ReviewPortal.CryptoChecks.Tests.csproj \
  --locked-mode --source "$HOME/.nuget/packages" -p:NuGetAudit=false
dotnet test app/ReviewPortal.CryptoChecks.Tests/ReviewPortal.CryptoChecks.Tests.csproj \
  --no-restore
dotnet publish app/ReviewPortal.CryptoChecks/ReviewPortal.CryptoChecks.csproj \
  --no-restore -c Release -p:UseAppHost=false \
  -o app/ReviewPortal.CryptoChecks/bin/qualification
```

The portable, framework-dependent DLL can run under the exact image's .NET 10
runtime; it does not carry a substitute runtime or native cryptographic library.
Publish does not modify or rebuild the portal image. The Mac build/test validates
compilation and pure policy/argument handling, **not** Linux native behavior.
Running on macOS produces an unsupported-platform report and exit 4, without
attempting native or managed crypto/network probes.

## Candidate image execution (not executed during local validation)

On a separately approved Linux x86_64 runner with the already-authorized private
registry access and container runtime, mount the published directory read-only:

```sh
docker run --rm --platform linux/amd64 --network none --read-only \
  --cap-drop ALL --security-opt no-new-privileges \
  -e DOTNET_EnableDiagnostics=0 \
  --mount "type=bind,source=$PWD/app/ReviewPortal.CryptoChecks/bin/qualification,target=/checks,readonly" \
  --entrypoint dotnet \
  "<private-registry>/<portal-repository>@sha256:<approved-app-image-digest>" \
  /checks/ReviewPortal.CryptoChecks.dll --timeout-seconds 45
```

Replace the generic image argument with the exact approved deployment image
from ignored operational records. Keep actual registry hostnames, image digests
and run/physical deployment IDs out of tracked examples. These commands neither
invoke ACR nor install anything. Do not substitute the host's OpenSSL, mount
provider libraries/configuration, change OPENSSL_* overrides, enable providers,
or alter property defaults to make a check pass. The image digest is an operator
target, not an attestation supplied by the process itself. An emulated/nonmatching
architecture or different platform requires its own operating-environment review.

## Native ACR qualification quick build (not executed locally)

Execute only after explicit approval of the exact build-pool capacity/cost plan.
Routing approval does not authorize build capacity or a billable ACR operation.
From the authoritative repository root, on the already-authorized execution host:

```sh
az acr build \
  --registry "<private-registry-name>" \
  --agent-pool "<approved-private-build-pool>" \
  --platform linux/amd64 \
  --image "crypto-observation:{{.Run.ID}}" \
  --file Dockerfile \
  --build-arg "SDK_IMAGE=<approved-dotnet10-sdk-repository>@sha256:<sdk-image-digest>" \
  --build-arg "APP_IMAGE=<private-registry>/<portal-repository>@sha256:<approved-app-image-digest>" \
  app/ReviewPortal.CryptoChecks
```

Both image arguments are mandatory and must carry a 64-character lowercase
SHA-256 digest. The SDK stage restores the dependency-free project with its
locked manifest and a NuGet configuration with all package sources/fallback
folders cleared; audit is disabled for this offline diagnostic restore. No
external feeds or dependency installations are needed. Publish is explicitly
framework-dependent, with no apphost. The narrow `.dockerignore` allowlist
excludes local receipts, `bin/obj`, tests, configuration, credentials and unrelated
source from the context.

The final stage inherits **the supplied application image**, without installing
packages, replacing crypto libraries or modifying OpenSSL/configuration/default
properties. Only root-owned, read-only published files under
`/opt/review-portal-crypto-checks/` are added. USER/WORKDIR/ENTRYPOINT/environment
remain inherited; the diagnostic RUN rejects any effective UID other than 1654
and checks that its directory and DLL are not writable. This build does not
rebuild the portal or replace the approved production image. The output is a
**diagnostic derivative image**, not an authorized production deployment image.

During RUN, the diagnostic writes JSON to the ACR build log only. No evidence
file is added to the portal filesystem. `DOTNET_EnableDiagnostics=0` is scoped
to that command, not persisted as an image ENV. If `timeout` exists, it enforces
60 seconds plus a 5-second kill grace; otherwise the harness's own 45-second
process deadline applies. TLS is not requested. Nonzero **exit 2** is deliberately
accepted only as completed-but-unqualified observations, with an explicit
`CRYPTO_OBSERVATION_EXIT=2 QUALIFIED=false` marker. Exit 0 is unexpected and fails,
as do operational errors, timeout/signals, unsupported platforms and invalid
arguments. A successful ACR run or derivative-image push is **not certification**.
Native execution, effective file modes, platform architecture and timeout-command
support still require checking in the approved ACR run; local static checks do
not prove them.

TLS is **opt-in**. Only on an approved private network, replace `--network none`
with the explicitly approved network and append:

```text
--tls-host <approved-private-DNS-hostname> --tls-port 443 --tls-timeout-seconds 10
```

Only a DNS hostname is accepted: no URL, IP literal, userinfo, path, query,
headers, bearer token or client certificate. One TCP/TLS handshake is performed;
no HTTP request or application authentication is sent. DNS, trust-chain building
and online certificate revocation may require additional network access; the
operator must approve those destinations and US-only processing boundaries.
Hostname/trust verification remains enabled. There is no certificate callback or
credential/hostname-check bypass. TLS 1.2 and online revocation are explicit;
the negotiated cipher suite is observed, **not declared approved**. The default
TLS deadline is 10 seconds (1–30), and must be shorter than the overall deadline.
The protocol restriction follows the selected SymCrypt certificate's TLS 1.2
approved-mode constraints, not a claim that TLS 1.3 is universally noncompliant.
The rebuilt portal image also restricts ECDHE groups through its SSL profile;
this diagnostic does not independently trace the negotiated group or TLS provider.

## Evidence and fail-explicit semantics

JSON contains runtime/architecture, OpenSSL version, loaded provider name/version/
status (sampled before any on-demand self-test), actual dispatch availability and conditional on-demand self-test result,
the default `fips` property predicate, default-context algorithm fetch providers,
OpenSSL public DRBG provider, functional managed SHA-256/RNG/RSA-2048 RS256 checks,
managed AES-GCM-256 known-answer/roundtrip/tamper observations,
and (if requested) authenticated TLS protocol/cipher configuration.

The separate `Encryption` object reports two fixed public
[NIST CAVP GCM vectors](https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Algorithm-Validation-Program/documents/mac/gcmtestvectors.zip)
from `gcmEncryptExtIV256.rsp`, Count=0 in each of the
Keylen=256/IVlen=96/Taglen=128 sections: PTlen=0/AADlen=0 and
PTlen=128/AADlen=128. Ciphertext and tag expected bytes are literal published
answers, not recomputed by the algorithm under test. The nonempty case expects
CT `8995ae2e6df3dbf96fac7b7137bae67f` and tag
`eca5aa77d51d4a0a14d9c51e1da474ab`; the empty case expects tag
`bdc1ac884d332457a1d2664f168c76f0`.

Each case encrypts once, compares both expected outputs, decrypts the independent
published answer, and checks an encryption/decryption roundtrip. Three additional
decrypt calls must reject separately modified ciphertext, tag and AAD with
`AuthenticationTagMismatchException`. For empty ciphertext/AAD, modification
inserts one byte. No general crypto error is mistaken for successful rejection.
The fixed bounds are two cases, 32-byte keys, 12-byte nonces, 16-byte tags and at
most 16-byte plaintext/AAD (17-byte tampered ciphertext only). Every `AesGcm`
instance is disposed and all working buffers are zeroed in `finally`. Test
keys/nonces are public, deterministic vector inputs, not production material or
a nonce-generation recommendation. JSON includes only case IDs, lengths and
booleans, never vector key/plaintext/ciphertext/tag bytes.

`Native.EncryptionCipherProvider` is the provider of this diagnostic's
`EVP_CIPHER_fetch(NULL, "AES-256-GCM", NULL)` result. That fetched cipher is freed
after observation. It **does not trace the actual .NET `AesGcm` or `SslStream`
contexts**, prove approved-mode operation, or establish FIPS 140-3 certificate
validation. Mac tests exercise managed functionality only; the CLI still requires
real Linux for runtime/native observations and still returns unqualified exit 2.

Provider enumeration uses the supplied default context; it does not explicitly
load or activate any provider. Fetches pass `NULL` properties (no new restriction
or fallback). Full effective default properties cannot be queried through the
public OpenSSL 3.3 API: this gap is explicit. Candidate config files are hashed,
not dumped or interpreted as effective settings. Includes/overrides and managed
context behavior require additional execution evidence. Loaded crypto/module
files are recorded by basename and SHA-256 from `/proc/self/maps`; missing or
multiple libcrypto mappings fail. SymCrypt's exact version/certificate/build
identity must be matched externally to those module hashes and the existing
nonsecret image-inspection receipt. No unknown SymCrypt native API is guessed.

SHA-256 checks the standard `abc` known answer using managed SHA256. RNG is only
a bounded managed smoke check (no entropy/statistical claim). Transient synthetic
RSA material checks RS256 verification of a valid signature and rejection of a
changed hash. No private material, signatures, random bytes, tokens, environment
dump or native exception message is printed. RSA key-provider queries use public
`RSAOpenSsl.DuplicateKeyHandle()` and public OpenSSL APIs. Imported RSA keys may
be legacy (`null` provider); a separately initialized verify context observes
signature-provider selection for that key but **does not trace .NET's actual
disposed verification context**. Default fetches also do not prove actual managed
SHA/RNG/TLS paths. These limitations deliberately prevent qualification.

More precisely: SHA-256/cipher/signature/key-management fetches select a provider
for this harness's fetched algorithm in libcrypto's default context; .NET may use
legacy digest objects, other contexts, provider caches or platform-native paths.
`RAND_get0_public()` describes OpenSSL's DRBG, **not** managed RNG routing or OS
entropy provenance. `EVP_PKEY_get0_provider()` identifies key management, not the
provider performing every signature operation; a legacy imported key has no
provider. `EVP_PKEY_CTX_get0_provider()` after the separate `verify_init` identifies
that surrogate context's signature provider before the RS256 hash/padding
parameters are applied; it neither observes .NET's actual verification context
nor establishes approved parameters. TLS protocol/cipher-suite observations do
not expose the provider of every handshake/record operation, nor platform ingress,
client, mesh or service crypto. A single loaded libcrypto mapping is only a guard
against passing a key pointer across different libraries, not operation attribution.

Crucially, OpenSSL's self-test API returns **1 even when a provider has no self-test
dispatch**. The harness checks dispatch ID 1031 first and reports `null` rather
than a misleading successful self-test when absent. SCOSSL v1.10.2 does not export
that dispatch; its automatic SymCrypt self-tests and approved-operation rules
require separate accepted evidence. If a dispatch exists, its result is collected
outside enumeration locks; a failure stops functional/TLS probes. An on-demand
self-test can put a provider in error state: run this only in an isolated
diagnostic process/container, never inside the production portal.

| Exit | Meaning |
| --- | --- |
| 2 | Observations completed without detected errors, but **unqualified**. |
| 3 | Missing library/API/provider, failed probe, metadata/module error, or deadline. |
| 4 | Unsupported non-Linux platform; no crypto/TLS probes run. |
| 64 | Invalid arguments; values are not echoed. |

There is intentionally **no runtime success/qualified exit 0**. Tests alone exit
0. `Qualified` is always false. The overall deadline defaults to 45 seconds
(5–120) and terminates even stuck native self-tests. A deadline emits a small
error record and discards partial evidence. Native crashes can terminate without
JSON; the runner must treat signals, absent/incomplete JSON and nonzero statuses
as failures, not approval. Transport/platform/CMVP certificate 5313 and its
security policy, approved operation, exact operating environment and deployment
boundary acceptance remain separate mandatory work.

## Verified public interface references

Inspected before binding public native interfaces:

All native delegates use C calling convention: opaque pointers/`const char *`
are `nint`, C `int` returns are `int`, fetch algorithm names use UTF-8, and
`OSSL_PROVIDER_do_all` uses an `int(pointer, pointer)` callback kept alive across
the synchronous call. `OSSL_PARAM` is a sequential `pointer, uint, pointer,
size_t, size_t` structure; `OSSL_DISPATCH` is `int, function pointer`. The
harness and cross-platform layout test verify the 64-bit ABI: parameter size
40 with offsets 0/8/16/24/32, dispatch size 16 with pointer offset 8. Unsupported
pointer sizes/layouts fail before loading libcrypto. Parameter types 1 (integer)
and 6 (UTF8 pointer) match `core.h`; requested storage is caller-owned and freed
after querying. Returned provider/algorithm/context metadata pointers are borrowed;
only fetched algorithm objects and the surrogate context are freed by the harness.

- [SCOSSL v1.10.2 provider base](https://github.com/microsoft/SymCrypt-OpenSSL/blob/v1.10.2/SymCryptProvider/src/p_scossl_base.c):
  provider parameters, `fips=yes` algorithm properties, and base dispatch table.
- [OpenSSL 3.3.7 core dispatch](https://github.com/openssl/openssl/blob/openssl-3.3.7/include/openssl/core_dispatch.h):
  `OSSL_FUNC_PROVIDER_SELF_TEST = 1031`.
- [OpenSSL 3.3.7 provider core](https://github.com/openssl/openssl/blob/openssl-3.3.7/crypto/provider_core.c):
  `ossl_provider_self_test()` returns 1 if the self-test function is absent.
- [OpenSSL provider APIs](https://docs.openssl.org/3.3/man3/OSSL_PROVIDER/),
  [EVP declarations](https://github.com/openssl/openssl/blob/openssl-3.3.7/include/openssl/evp.h),
  [provider-context implementation](https://github.com/openssl/openssl/blob/openssl-3.3.7/crypto/evp/pmeth_lib.c):
  public pointer/callback/parameter ABI and signature-context provider query.
- [.NET runtime v10.0.0 RSA native implementation](https://github.com/dotnet/runtime/blob/v10.0.0/src/native/libs/System.Security.Cryptography.Native/pal_evp_pkey_rsa.c):
  legacy `EVP_PKEY_set1_RSA` import, RSA generation and verify-context creation.
  This reference version is **not** an attestation of the image's patched 10.0.12
  runtime. Exact patched-source/build mapping remains required.
