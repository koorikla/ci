# koorikla/ci

Portable build, test, scan, sign and attest **scripts** plus a multi-arch **toolbox image**
for everything koorikla ships: Go, Python, Node.js (Express, Fastify, NestJS, Nuxt,
SvelteKit, Remix), Next.js, Rust, Java (Quarkus, Spring Boot), Elixir/Phoenix, Ruby/Rails,
Helm charts, Crossplane configuration packages and Crossplane providers.

- **Primary path: in-cluster.** OpenChoreo workflow-plane ClusterWorkflows run
  `scripts/<stack>/*.sh` and `scripts/common/*.sh` inside
  `ghcr.io/koorikla/ci-toolbox` (see [Running in-cluster](#running-in-cluster-openchoreo-workflow-plane)).
- **Optional path: GitHub Actions.** Thin reusable workflows that only wire inputs to the
  same scripts (plus GitHub-only extras: CodeQL, SARIF upload, GitHub attestations,
  keyless signing). Nothing stack-specific is inlined in YAML.

Both paths produce the same thing: a **multi-arch** (`linux/amd64` + `linux/arm64`) artifact,
Trivy-scanned per platform, with an SPDX SBOM, provenance, a cosign signature and a cosign
vulnerability attestation.

## Toolbox image

`ghcr.io/koorikla/ci-toolbox` — stable tag **`v1`** (moves with the `v1` git tag), plus
`main`, `<short sha>` and `<full sha>`. Multi-arch, itself scanned, SBOM'd, attested and
cosign-signed by [`toolbox.yaml`](.github/workflows/toolbox.yaml). Pin by digest in cluster
manifests (`ghcr.io/koorikla/ci-toolbox:v1@sha256:…`).

Contents ([`toolbox/Dockerfile`](toolbox/Dockerfile), versions pinned, release checksums verified
where upstream publishes them): trivy, syft, cosign, crane, helm, yq, jq, git, crossplane CLI,
bash, curl, make. Scripts live in `/opt/koorikla-ci/scripts` (`$CI_SCRIPTS`), `common/` is on
`PATH`, user is uid 65532, workdir `/workspace`. `toolbox-smoke` checks every tool.

It deliberately has **no image builder**: in-cluster image builds use BuildKit (or kaniko) in
their own step, then hand the pushed digest to the toolbox steps.

## GitHub Actions wrappers (optional)

| Workflow | What it does | Pushes |
|---|---|---|
| [`container.yaml`](.github/workflows/container.yaml) | Shared building block: multi-arch buildx build, Trivy scan of every platform (SARIF → code scanning), syft SBOM, attestations, cosign sign | image `ghcr.io/<owner>/<repo>` |
| [`go.yaml`](.github/workflows/go.yaml) | setup-go from go.mod, `go vet`, golangci-lint, `go test -race` + coverage, govulncheck, CodeQL → `container.yaml` | image |
| [`python.yaml`](.github/workflows/python.yaml) | uv (`uv lock --check`, `uv sync --frozen`), ruff check + format, mypy (if locked), pytest + coverage, pip-audit, Trivy fs on uv.lock, CodeQL → `container.yaml` (distroless Python) | image |
| [`node.yaml`](.github/workflows/node.yaml) | Generic Node.js (Express, Fastify, NestJS, Nuxt, SvelteKit, Remix): package manager from `packageManager` / lockfile (pnpm, yarn via corepack), frozen install, lint / typecheck / test / build scripts if present, prod-deps audit, Trivy fs, CodeQL → `container.yaml` (distroless Node.js, `start_entry`) | image |
| [`rust.yaml`](.github/workflows/rust.yaml) | rust-toolchain.toml, `cargo fmt --check`, clippy `-D warnings`, cargo-nextest + doctests, cargo-deny, cargo-audit, Trivy fs, CodeQL, rust-cache → `container.yaml` (static musl binary on distroless/static) | image |
| [`java.yaml`](.github/workflows/java.yaml) | Maven or Gradle (wrapper, auto-detected), Temurin 25, tests + JaCoCo, CycloneDX SBOM scanned by Trivy + osv-scanner, CodeQL → `container.yaml`: Quarkus JVM (default), opt-in Quarkus native (Mandrel, per arch), Spring Boot layered jar on distroless Java | image |
| [`workload-bump.yaml`](.github/workflows/workload-bump.yaml) | GitOps hand-off after a stack workflow: OpenChoreo Workload `spec.container.image` → `<repo>:<sha>@sha256:<digest>`, `spec.source.commit`, commit + push `[skip ci]` | commit |
| [`nextjs.yaml`](.github/workflows/nextjs.yaml) | setup-node (.nvmrc / .node-version / .tool-versions / engines), npm/pnpm/yarn by lockfile, lint, typecheck, test, cached `next build`, audit, Trivy fs, CodeQL → `container.yaml` | image |
| [`elixir.yaml`](.github/workflows/elixir.yaml) | setup-beam (.tool-versions), deps/_build cache, `compile --warnings-as-errors`, `format --check-formatted`, credo, `mix test` (+ optional Postgres), sobelow, `hex.audit`, `deps.audit`, Trivy fs → `container.yaml` | image |
| [`ruby.yaml`](.github/workflows/ruby.yaml) | setup-ruby with bundler cache, rubocop, rspec / `rails test` / `rake test` (+ optional Postgres), brakeman (Rails), bundler-audit, Trivy fs, CodeQL → `container.yaml` | image |
| [`helm-chart.yaml`](.github/workflows/helm-chart.yaml) | `helm lint --strict`, helm-unittest, package, push as OCI, cosign sign, provenance | chart `oci://ghcr.io/<owner>/charts/<name>` |
| [`crossplane-configuration.yaml`](.github/workflows/crossplane-configuration.yaml) | pinned Crossplane CLI, `crossplane resource validate` (package + examples + rendered output), `crossplane composition render` tests with expected-output diff, `xpkg build`, push, cosign sign, provenance | xpkg |
| [`crossplane-provider.yaml`](.github/workflows/crossplane-provider.yaml) | generate-is-clean check, vet/test/govulncheck/lint, multi-arch controller image via `container.yaml`, one xpkg per arch with the controller embedded, pushed as one multi-arch package, cosign sign, provenance | controller image + xpkg |

## Adopt: one file in your repo

```yaml
# .github/workflows/ci.yaml
name: ci
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  go:
    uses: koorikla/ci/.github/workflows/go.yaml@v1
    permissions: {contents: read, actions: read, packages: write, id-token: write, attestations: write, security-events: write}
```

Ready-to-copy callers for every stack are in [`templates/workflows/`](templates/workflows),
Dependabot configs in [`templates/dependabot/`](templates/dependabot) and Dockerfiles in
[`templates/dockerfiles/`](templates/dockerfiles) (Go distroless cross-compiled, Python on
distroless Python, generic Node.js and Next.js standalone on distroless Node, Rust static musl
on distroless static, Quarkus JVM / Quarkus native / Spring Boot layered jar, Elixir release on
debian-slim, Rails/Ruby slim). The callers for the new stacks (python, node, rust, java) include
the [Workload bump](#workload-bump-gitops-hand-off) job.

**Permissions matter.** A reusable workflow's jobs can never get more than the calling job
grants; if a nested job asks for more, GitHub fails the whole run at startup
(`startup_failure`, "workflow file issue", no jobs). Grant exactly the set listed in the
header comment of each workflow:

| Workflow | Caller job permissions |
|---|---|
| go, python, node, nextjs, rust, java, ruby, crossplane-provider | `contents: read`, `actions: read`, `packages: write`, `id-token: write`, `attestations: write`, `security-events: write` |
| container, elixir | same without `actions: read` |
| helm-chart, crossplane-configuration | `contents: read`, `packages: write`, `id-token: write`, `attestations: write` |
| workload-bump | `contents: write` (only this job: it pushes the Workload commit) |

`push: true` (default) only pushes on non-`pull_request` events; PRs build (amd64), test
and scan but never push or sign. For a registry other than GHCR pass `registry:` plus the
`registry_username` / `registry_password` secrets.

## What gets checked, per stack

| Stack | Lint / static analysis | Tests | Dependency vulns | SAST | Image |
|---|---|---|---|---|---|
| Go | `go vet`, golangci-lint | `go test -race` + coverage | govulncheck (call-graph aware) | CodeQL go | Trivy, SBOM, sign |
| Python | ruff check + `ruff format --check`, mypy (if locked), `uv lock --check` | pytest (+ pytest-cov coverage) | pip-audit on the exported runtime requirements (hashes), Trivy fs on uv.lock | CodeQL python | Trivy, SBOM, sign |
| Node.js | `lint` script, `typecheck` script / `tsc --noEmit` | `test` script, `build` script | `npm audit` / `pnpm audit` / `yarn npm audit` (prod deps, `audit_level`), Trivy fs on the lockfile | CodeQL javascript-typescript | Trivy, SBOM, sign |
| Rust | `cargo fmt --check`, clippy `-D warnings` | cargo-nextest (+ doctests) or `cargo test` | cargo-deny (advisories, bans, licenses with deny.toml, sources), cargo-audit, Trivy fs on Cargo.lock | CodeQL rust | Trivy, SBOM, sign |
| Java (Quarkus, Spring Boot) | compile (`verify` / `build`) | JUnit via Maven/Gradle + JaCoCo line coverage | CycloneDX SBOM of the resolved runtime deps scanned by Trivy (`trivy sbom`) and osv-scanner (CVSS gate) | CodeQL java-kotlin | Trivy, SBOM, sign |
| Next.js | `lint` script (eslint), `typecheck` script / `tsc --noEmit` | `test` script, `next build` | `npm audit` / `pnpm audit` / `yarn npm audit` (prod deps, `audit_level`), Trivy fs on the lockfile | CodeQL javascript-typescript | Trivy, SBOM, sign |
| Elixir | `compile --warnings-as-errors`, `format --check-formatted`, credo `--strict` (if a dependency) | `mix test` (+ Postgres service) | `mix hex.audit` (retired), `mix deps.audit` (mix_audit, if a dependency), Trivy fs on mix.lock | sobelow (if a dependency, i.e. Phoenix). **CodeQL has no Elixir support.** | Trivy, SBOM, sign |
| Ruby / Rails | rubocop (if bundled) | rspec / `bin/rails test` / `rake test` (+ Postgres) | bundler-audit, Trivy fs on Gemfile.lock | brakeman (Rails), CodeQL ruby | Trivy, SBOM, sign |
| Helm | `helm lint --strict` | helm-unittest (`<chart>/tests/`) | - | - | chart signed + provenance |
| Crossplane configuration | `crossplane resource validate` of XRDs/Compositions/function inputs against Crossplane + dependency schemas | `crossplane composition render` per example XR, composed resources validated, diff vs expected | - | - | xpkg signed + provenance |
| Crossplane provider | `make generate` must leave a clean tree, `go vet`, golangci-lint | `go test -race` | govulncheck | CodeQL go (opt-in: slow on upjet) | controller image: Trivy, SBOM, sign; xpkg signed |

Limits: images are scanned with Trivy for OS + language packages; `trivy_ignore_unfixed: true`
by default; the job fails on `trivy_severity` (default `CRITICAL`). The SBOM attached to a
multi-arch image is generated from the `linux/amd64` variant (Trivy scans every platform).
Images are pushed before they are scanned (multi-arch images cannot be loaded into the
runner's daemon); a failing scan leaves an **unsigned** image that admission control rejects.

### Accepting a risk

Pass `trivy_ignore_file: path/to/.trivyignore.yaml` (works for image and lockfile scans).
Use the YAML form with a `statement` and `expired_at` so exceptions expire, e.g.
[`fixtures/ruby/.trivyignore.yaml`](fixtures/ruby/.trivyignore.yaml).

## Multi-arch

`container.yaml` builds `platforms` (default `linux/amd64,linux/arm64`):

- `multiarch_strategy: native` (default): one job per platform on `ubuntu-24.04` and
  `ubuntu-24.04-arm`, each pushed by digest, then merged with `docker buildx imagetools create`
  into one OCI index carrying all tags. Fast and no emulation. arm64 hosted runners are free
  for public repos; for private repos check your plan, or use `qemu`.
- `multiarch_strategy: qemu`: one amd64 runner, buildx + QEMU.

The index **and** every platform manifest are cosign-signed (`--recursive`); attestations are
attached to the index digest (what pods reference). Dockerfiles for compiled languages should
cross-compile with `FROM --platform=$BUILDPLATFORM` (see the Go template); Node, Ruby and
Elixir images build on the target platform because native modules / ERTS are arch-specific.
Python and Rust build on the target platform too (arch-specific wheels; native musl build on each
runner, no cross toolchain). Java JVM images (Quarkus, Spring Boot) build the jar once on
`$BUILDPLATFORM` and copy it into each platform's distroless Java runtime; the Quarkus native
image (Mandrel cannot cross-compile) builds on each arch's native runner.

## Signing and attestation model

GitHub-built artifacts are signed **keyless** (Sigstore Fulcio + Rekor) with the job's OIDC
token. Because signing happens inside a *reusable* workflow, the certificate identity is the
reusable workflow, and the calling repository is recorded in certificate extensions. Every
stack workflow (go, python, node, rust, java, nextjs, elixir, ruby) signs through
`container.yaml`, so the identity is the same for all of them:

| Certificate field | Value |
|---|---|
| Issuer | `https://token.actions.githubusercontent.com` |
| Subject (SAN) | `https://github.com/koorikla/ci/.github/workflows/{container,helm-chart,crossplane-configuration,crossplane-provider}.yaml@refs/tags/v1` |
| `githubWorkflowRepository` (1.3.6.1.4.1.57264.1.5) | caller, e.g. `koorikla/hello-world` |
| `githubWorkflowRef` (1.3.6.1.4.1.57264.1.6) | caller ref, e.g. `refs/heads/main` |
| Build Config URI | caller workflow, e.g. `https://github.com/koorikla/hello-world/.github/workflows/ci.yaml@refs/heads/main` |

So the identity `https://github.com/koorikla/<repo>/.github/workflows/<file>@refs/heads/main`
is the *caller*; it is carried in the extensions, not the SAN. **Always pin the caller
repository/ref as well as the subject:** `koorikla/ci` is public, so any repository can call
its workflows and obtain a certificate with the same SAN.

```sh
cosign verify ghcr.io/koorikla/hello-world:<sha> \
  --certificate-identity https://github.com/koorikla/ci/.github/workflows/container.yaml@refs/tags/v1 \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-github-workflow-repository koorikla/hello-world \
  --certificate-github-workflow-ref refs/heads/main
# GitHub attestations (SLSA provenance + SPDX SBOM):
gh attestation verify oci://ghcr.io/koorikla/hello-world:<sha> --owner koorikla
```

Attached to every pushed image (index digest):

| Attestation | Producer | Predicate type |
|---|---|---|
| Signature | cosign (keyless) | - |
| SLSA build provenance | `actions/attest-build-provenance` (OCI referrer) | `https://slsa.dev/provenance/v1` |
| SBOM | `actions/attest` with `sbom-path` (OCI referrer) | `https://spdx.dev/Document/v2.3` |
| Vulnerability scan | `cosign attest --type vuln` (Trivy cosign-vuln) | `https://cosign.sigstore.dev/attestation/vuln/v1` |

In-cluster builds use the same scripts but sign with the platform key
(`COSIGN_KEY=k8s://<ns>/<secret>` or a KMS URI, see `scripts/common/sign-image.sh`); the
admission policy accepts **either** attestor.

Kyverno (illustrative only; the real policy lives in koorikla/platform):

```yaml
# apiVersion: kyverno.io/v1
# kind: ClusterPolicy
# metadata:
#   name: verify-koorikla-images
# spec:
#   validationFailureAction: Enforce
#   webhookTimeoutSeconds: 30
#   rules:
#     - name: hello-world-signed-by-ci
#       match:
#         any:
#           - resources:
#               kinds: [Pod]
#       verifyImages:
#         - imageReferences: ["ghcr.io/koorikla/hello-world*"]
#           mutateDigest: true
#           verifyDigest: true
#           required: true
#           attestors:
#             - count: 1                      # GitHub keyless OR platform key
#               entries:
#                 - keyless:
#                     issuer: https://token.actions.githubusercontent.com
#                     subjectRegExp: '^https://github\.com/koorikla/ci/\.github/workflows/container\.yaml@refs/tags/v[0-9]+$'
#                     additionalExtensions:
#                       githubWorkflowRepository: koorikla/hello-world
#                       githubWorkflowRef: refs/heads/main
#                     rekor:
#                       url: https://rekor.sigstore.dev
#                 - keys:
#                     kms: k8s://kyverno/platform-cosign-pub   # in-cluster builds
#           attestations:
#             - type: https://cosign.sigstore.dev/attestation/vuln/v1
#               attestors:
#                 - entries:
#                     - keyless:
#                         issuer: https://token.actions.githubusercontent.com
#                         subjectRegExp: '^https://github\.com/koorikla/ci/\.github/workflows/container\.yaml@refs/tags/v[0-9]+$'
#                         additionalExtensions:
#                           githubWorkflowRepository: koorikla/hello-world
#               conditions:
#                 - all:
#                     - key: "{{ time_since('','{{metadata.scanFinishedOn}}','') }}"
#                       operator: LessThanOrEquals
#                       value: "168h"
```

cosign v3 stores signatures/attestations in the Sigstore bundle format (OCI referrers); make
sure the Kyverno version in the platform verifies that format (see VERIFY in the platform repo).

## Workload bump (GitOps hand-off)

[`workload-bump.yaml`](.github/workflows/workload-bump.yaml) points the app's OpenChoreo
Workload (`deploy/openchoreo/workload.yaml` by default) at the image the stack workflow just
pushed and commits it back (`chore(deploy): bump <name> image to <sha> [skip ci]`):

```yaml
  bump:
    needs: python
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    uses: koorikla/ci/.github/workflows/workload-bump.yaml@v1
    permissions:
      contents: write
    with:
      image: ${{ needs.python.outputs.image }}     # <repo>:<short sha>
      digest: ${{ needs.python.outputs.digest }}   # index digest; '' (PRs) skips the bump
```

- `spec.container.image` becomes `<repo>:<short sha>@sha256:<index digest>` (production admission
  only accepts digest references; the tag keeps it readable), `spec.source.commit` the built commit.
  The edit is line-based (`scripts/common/workload-bump.sh`, bash + awk): comments survive.
- It is a separate reusable workflow so only that job holds `contents: write`; the stack
  workflows keep their read-only permission set (a nested job asking for more than the caller
  grants fails the whole run at startup).
- Push-triggered callers should `paths-ignore: ['deploy/**']`; branch protection must let the
  job token push. `validate_command` runs a schema check before committing; `push: false` is a
  dry run (used by the selftest).
- In-cluster builds use the same two scripts (`workload-bump.sh`, `git-push-change.sh`).

## Registry: GHCR now, Harbor later

Everything pushes to `ghcr.io/<owner>` by default. Harbor on the management cluster currently
**proxy-caches ghcr.io**, so clusters pull through Harbor while signatures/attestations stay
verifiable (same digests). To push to Harbor later set `registry: harbor.<domain>/<project>`
and pass a robot account as `registry_username` / `registry_password`.

GHCR packages are private when first created: make them public (package settings) or give the
pulling clusters credentials.

## Running in-cluster (OpenChoreo workflow plane)

Each step is "run a script in the toolbox with these env vars, read files from
`$CI_OUT_DIR`". Typical pipeline for a service image:

| Step | Image | Command | Key env in | Files out (`$CI_OUT_DIR`) |
|---|---|---|---|---|
| checks | toolbox (+ language toolchain image, see below) | `$CI_SCRIPTS/<stack>/check.sh` | `WORKDIR`, stack flags | coverage etc. |
| deps scan | toolbox | `scan-fs.sh` | `SCAN_PATH`, `FAIL_SEVERITIES`, `IGNORE_FILE` | `trivy-fs.json`, `trivy-fs.sarif` |
| coordinates | toolbox | `image-meta.sh` | `OWNER`, `REPO_NAME`, `SHA`, `REGISTRY`, `IMAGE_NAME` | `repo`, `image`, `short_sha`, … |
| build + push | BuildKit | `buildctl build … --opt platform=linux/amd64,linux/arm64 --output type=image,name=<repo>:<tag>,push=true` | | image index digest |
| scan | toolbox | `scan-image.sh` | `IMAGE_REF=<repo>@sha256:…`, `IMAGE_SRC=remote`, `PLATFORMS` | `trivy-*.json`, `trivy.sarif`, `trivy-vuln.json` |
| SBOM | toolbox | `sbom.sh` | `IMAGE_REF`, `SOURCE=registry` | `sbom.spdx.json` |
| sign + attest | toolbox | `sign-image.sh` | `IMAGE_DIGEST_REF`, `VULN_PREDICATE`, `COSIGN_KEY=k8s://<ns>/<secret>` | `signed_ref` |

Add `cosign attest --key "$COSIGN_KEY" --type spdxjson --predicate sbom.spdx.json` (and a
SLSA predicate from the workflow engine, if it emits one) for SBOM/provenance attestations;
GitHub's `attest-*` actions have no in-cluster equivalent.

Stack checks need a language toolchain the toolbox does not carry: run `check.sh` in the
official toolchain image (`golang`, `ghcr.io/astral-sh/uv:python3.13-trixie`, `node`, `rust`,
`eclipse-temurin:25-jdk`, `elixir`, `ruby`, `alpine/helm`) with the scripts
mounted or copied from the toolbox (`/opt/koorikla-ci/scripts`), exactly like a developer runs
them on a laptop. Crossplane steps (`crossplane/*.sh`) run in the toolbox itself;
`validate-render.sh` needs a Docker-compatible runtime for `crossplane composition render`
(functions run as containers) — provide a DinD sidecar or run render tests only on GitHub.

Illustrative Argo Workflows template (OpenChoreo's workflow plane is Argo-based; the real
ClusterWorkflow lives in koorikla/platform):

```yaml
# apiVersion: argoproj.io/v1alpha1
# kind: ClusterWorkflowTemplate
# metadata:
#   name: koorikla-scan-sign
# spec:
#   templates:
#     - name: scan-sign
#       inputs:
#         parameters:
#           - name: image-digest-ref        # ghcr.io/koorikla/app@sha256:...
#       container:
#         image: ghcr.io/koorikla/ci-toolbox:v1@sha256:<digest>
#         command: [bash, -euo, pipefail, -c]
#         args:
#           - |
#             IMAGE_REF="{{inputs.parameters.image-digest-ref}}" IMAGE_SRC=remote scan-image.sh
#             IMAGE_REF="{{inputs.parameters.image-digest-ref}}" SOURCE=registry sbom.sh
#             IMAGE_DIGEST_REF="{{inputs.parameters.image-digest-ref}}" \
#               VULN_PREDICATE="$CI_OUT_DIR/trivy-vuln.json" sign-image.sh
#         env:
#           - {name: CI_OUT_DIR, value: /workspace/out}
#           - {name: PLATFORMS, value: "linux/amd64,linux/arm64"}
#           - {name: COSIGN_KEY, value: "k8s://ci/platform-cosign"}
#           - {name: DOCKER_CONFIG, value: /docker}  # registry creds (Secret mounted at /docker/config.json)
```

## Script contract (both runners)

Workflows are thin: each step calls `scripts/<stack>/*.sh` or `scripts/common/*.sh`, fetched from
`koorikla/ci` at **the same commit as the running reusable workflow** (`job.workflow_sha`).

- **Env in, files out.** Inputs are environment variables documented in each script header.
  File outputs go to `$CI_OUT_DIR` (default `./.ci-out`); every scalar output is also written to
  `$CI_OUT_DIR/<key>` and, under GitHub Actions, to `$GITHUB_OUTPUT`.
- **Portable:** bash 3.2 (macOS `/bin/bash`) and BSD/GNU userland; shellcheck-clean
  (`.shellcheckrc`, enforced by the selftest). No `sed -i`, `readlink -f`, `mapfile`,
  associative arrays or `${var,,}`.
- **Tools:** whatever the script `require_cmd`s; all of them ship in the toolbox.

| Script | Purpose |
|---|---|
| `common/image-meta.sh` | image coordinates (repo, short sha, push decision) |
| `common/build-matrix.sh` | per-arch runner matrix |
| `common/merge-manifest.sh` | per-arch digests → tagged OCI index |
| `common/scan-image.sh` | Trivy per platform → JSON, SARIF, cosign-vuln predicate, gate |
| `common/scan-fs.sh` | Trivy fs on lockfiles → JSON, SARIF, gate |
| `common/sbom.sh` | syft SPDX JSON |
| `common/sign-image.sh` | cosign sign (+ vuln attest), keyless or `COSIGN_KEY` |
| `common/scan-fs.sh` with `SBOM_FILE` | `trivy sbom` on a build-generated CycloneDX SBOM (Java) |
| `common/osv-scan.sh` | osv-scanner (pinned, checksum-verified install) on lockfiles / SBOM, CVSS gate |
| `common/workload-bump.sh` | OpenChoreo Workload image `<repo>:<tag>@sha256:…` + source commit |
| `common/git-push-change.sh` | commit paths if changed, push with rebase/retry |
| `common/generate-check.sh` | code generation must leave a clean tree |
| `go/check.sh`, `python/check.sh`, `node/{detect,setup-pm,check}.sh`, `nextjs/{detect,check}.sh`, `rust/check.sh`, `java/{detect,check}.sh`, `elixir/check.sh`, `ruby/check.sh`, `helm/{check,package-push,registry-meta}.sh` | stack checks |
| `crossplane/{install-cli,package-name,validate-render,xpkg-build,xpkg-push,provider-xpkg}.sh` | Crossplane CLI, validation/render tests, packaging |

## Versioning

Callers pin `@v1` (workflows) and `ci-toolbox:v1` (image). `v1` is a **moving, lightweight**
tag on `main`, moved only after the selftest is green; pushing it rebuilds
`ghcr.io/koorikla/ci-toolbox:v1` from the same commit:

```sh
git tag -f v1 <sha> && git push -f origin v1
```

Actions in the python, node, rust, java and workload-bump workflows (and the selftest) are
pinned by commit SHA with the release as a comment; Dependabot (`github-actions`) bumps them.

Keep it lightweight: with an annotated `v1`, nested `$/` workflow references failed with
"workflow was not found". Backwards-incompatible changes (renamed inputs, new required
permissions) go to `v2`. Reusable workflows call siblings with `uses: $/.github/workflows/…`
and fetch scripts at `job.workflow_sha`, so a caller pinned to `@v1` or a full SHA gets one
consistent set of workflows and scripts.

## Self-tests

[`selftest.yaml`](.github/workflows/selftest.yaml) runs every workflow against
[`fixtures/`](fixtures) on PRs, `workflow_dispatch`, and pushes to `main` touching
`.github/**`, `fixtures/**`, `scripts/**` or `tests/**`: actionlint + shellcheck, a bash 3.2
syntax check of every script plus script unit tests ([`tests/scripts/`](tests/scripts)), Go
module, uv project (WSGI on waitress), pnpm Fastify/TypeScript API, dependency-free Rust HTTP
service (cargo-deny with deny.toml), Quarkus REST service (Maven; JVM and native images), Spring
Boot service (Gradle, Kotlin DSL), Next.js app, mix project (credo + mix_audit, no Phoenix so
sobelow skips), Rack app (rspec, rubocop, bundler-audit), a Workload bump dry run, Helm chart (helm-unittest), Crossplane configuration (XRD + Composition with
function-go-templating + example XR + expected render), and a tiny native provider skeleton
(generator, controller image, per-arch xpkg). Pushed artifacts:

| Package | Kind |
|---|---|
| `ghcr.io/koorikla/ci-selftest-go` | image |
| `ghcr.io/koorikla/ci-selftest-python` | image |
| `ghcr.io/koorikla/ci-selftest-node` | image |
| `ghcr.io/koorikla/ci-selftest-rust` | image |
| `ghcr.io/koorikla/ci-selftest-java-quarkus` | image (JVM) |
| `ghcr.io/koorikla/ci-selftest-java-quarkus-native` | image (native) |
| `ghcr.io/koorikla/ci-selftest-java-spring` | image |
| `ghcr.io/koorikla/ci-selftest-nextjs` | image |
| `ghcr.io/koorikla/ci-selftest-elixir` | image |
| `ghcr.io/koorikla/ci-selftest-ruby` | image |
| `ghcr.io/koorikla/ci-selftest-helm` | Helm chart (OCI) |
| `ghcr.io/koorikla/ci-selftest-crossplane-configuration` | xpkg |
| `ghcr.io/koorikla/ci-selftest-crossplane-provider` | xpkg (multi-arch) |
| `ghcr.io/koorikla/ci-selftest-crossplane-provider-controller` | image |
| `ghcr.io/koorikla/ci-toolbox` | image |

Local checks before pushing: `actionlint && shellcheck -x scripts/*/*.sh tests/scripts/*.sh &&
bash tests/scripts/workload-bump.test.sh`.

## Workflow reference

Secrets for every workflow except workload-bump: `registry_username`, `registry_password` (optional; GHCR uses
`GITHUB_TOKEN`).

### container.yaml

| Input | Type | Default | Description |
|---|---|---|---|
| `image_name` | string | `''` | Image name (default: repository name) |
| `registry` | string | `''` | Registry prefix, e.g. ghcr.io/koorikla or harbor.example.com/apps (default ghcr.io/<owner>) |
| `context` | string | `.` | Docker build context |
| `dockerfile` | string | `Dockerfile` | Path to the Dockerfile |
| `platforms` | string | `linux/amd64,linux/arm64` | Comma-separated target platforms (PR builds are linux/amd64 only) |
| `build_args` | string | `''` | Newline-separated extra build-args (VERSION=<short sha> is always set) |
| `push` | boolean | `true` | Push, attest and sign on non-PR events |
| `trivy_severity` | string | `CRITICAL` | Comma-separated severities that fail the Trivy scan |
| `trivy_ignore_unfixed` | boolean | `true` | Ignore vulnerabilities without a fixed version |
| `trivy_fail` | boolean | `true` | Fail the job on findings at trivy_severity (false = report only) |
| `trivy_ignore_file` | string | `''` | Repo-relative .trivyignore(.yaml) with accepted risks (empty = none) |
| `upload_sarif` | boolean | `true` | Upload Trivy SARIF to GitHub code scanning |
| `sarif_category` | string | `''` | Code-scanning category (default container-<image>) |
| `artifact_name` | string | `''` | If set, download this workflow artifact into <context> before building (e.g. a prebuilt binary or xpkg inputs) |
| `multiarch_strategy` | string | `native` | native = one runner per arch (ubuntu-24.04 + ubuntu-24.04-arm) merged into one manifest list; qemu = single amd64 runner with buildx + QEMU |
| `runner_amd64` | string | `ubuntu-24.04` | Runner label for linux/amd64 builds |
| `runner_arm64` | string | `ubuntu-24.04-arm` | Runner label for linux/arm64 builds (native strategy) |

Outputs: `image`, `image_ref`, `image_repo`, `digest`, `image_digest_ref`, `short_sha`

### go.yaml

| Input | Type | Default | Description |
|---|---|---|---|
| `working_directory` | string | `.` | Go module directory |
| `go_version_file` | string | `''` | go.mod / .go-version used by setup-go (default <working_directory>/go.mod) |
| `run_lint` | boolean | `true` | Run golangci-lint |
| `golangci_lint_version` | string | `latest` | golangci-lint version |
| `run_vulncheck` | boolean | `true` | Run govulncheck |
| `run_codeql` | boolean | `true` | Run CodeQL (go) |
| `extra_test_cmd` | string | `''` | Extra shell command run in working_directory after tests |
| `build_container` | boolean | `true` | Build/scan/sign the container image after checks |
| `image_name` | string | `''` | Image name (default: repository name) |
| `registry` | string | `''` | Registry prefix (default ghcr.io/<owner>) |
| `context` | string | `''` | Docker build context (default working_directory) |
| `dockerfile` | string | `''` | Dockerfile (default <working_directory>/Dockerfile) |
| `platforms` | string | `linux/amd64,linux/arm64` | Comma-separated image platforms |
| `multiarch_strategy` | string | `native` | native (per-arch runners) or qemu |
| `build_args` | string | `''` | Newline-separated extra build-args |
| `push` | boolean | `true` | Push, attest and sign on non-PR events |
| `trivy_severity` | string | `CRITICAL` | Severities that fail the image scan |
| `trivy_ignore_unfixed` | boolean | `true` | Ignore unfixed vulnerabilities |
| `trivy_ignore_file` | string | `''` | Repo-relative .trivyignore(.yaml) with accepted risks |
| `trivy_fail` | boolean | `true` | Fail on findings at trivy_severity |

Outputs: `image`, `image_ref`, `image_repo`, `digest`, `image_digest_ref`, `short_sha`

### python.yaml

| Input | Type | Default | Description |
|---|---|---|---|
| `working_directory` | string | `.` | Directory containing pyproject.toml and uv.lock |
| `python_version` | string | `''` | Python version (default: .python-version / requires-python, installed by uv) |
| `uv_version` | string | `''` | uv version (default: [tool.uv] required-version or latest) |
| `run_lint` | boolean | `true` | Run ruff check + ruff format --check |
| `run_typecheck` | string | `auto` | Run mypy: 'auto' (when locked), 'true' or 'false' |
| `run_test` | boolean | `true` | Run pytest (coverage with pytest-cov) |
| `test_args` | string | `''` | Extra pytest arguments |
| `run_audit` | boolean | `true` | Run pip-audit on the runtime dependencies |
| `audit_ignore` | string | `''` | Space-separated vulnerability IDs pip-audit ignores (accepted risks) |
| `run_codeql` | boolean | `true` | Run CodeQL (python) |
| `build_container` | boolean | `true` | Build/scan/sign the container image after checks |
| `image_name` | string | `''` | Image name (default: repository name) |
| `registry` | string | `''` | Registry prefix (default ghcr.io/<owner>) |
| `context` | string | `''` | Docker build context (default working_directory) |
| `dockerfile` | string | `''` | Dockerfile (default <working_directory>/Dockerfile) |
| `platforms` | string | `linux/amd64,linux/arm64` | Comma-separated image platforms |
| `multiarch_strategy` | string | `native` | native (per-arch runners) or qemu |
| `build_args` | string | `''` | Newline-separated extra build-args |
| `push` | boolean | `true` | Push, attest and sign on non-PR events |
| `trivy_severity` | string | `CRITICAL` | Severities that fail the Trivy scans (image and lockfiles) |
| `trivy_ignore_unfixed` | boolean | `true` | Ignore unfixed vulnerabilities |
| `trivy_ignore_file` | string | `''` | Repo-relative .trivyignore(.yaml) with accepted risks |
| `trivy_fail` | boolean | `true` | Fail on Trivy findings at trivy_severity |

Outputs: `image`, `image_ref`, `image_repo`, `digest`, `image_digest_ref`, `short_sha`

### node.yaml

| Input | Type | Default | Description |
|---|---|---|---|
| `working_directory` | string | `.` | Directory containing package.json |
| `node_version` | string | `''` | Node.js version (overrides .nvmrc/.node-version/.tool-versions/package.json engines) |
| `run_lint` | boolean | `true` | Run the lint script (if defined) |
| `run_typecheck` | boolean | `true` | Run the typecheck script (or tsc --noEmit) |
| `run_test` | boolean | `true` | Run the test script (if defined) |
| `lint_script` | string | `lint` | package.json script used for lint |
| `test_script` | string | `test` | package.json script used for tests |
| `build_script` | string | `build` | package.json script that builds the app (CI and image; skipped when undefined) |
| `start_entry` | string | `''` | JS entry the image starts with node, relative to the app dir (START_ENTRY build arg, e.g. dist/main.js, .output/server/index.mjs, build/index.js; '' = Dockerfile default) |
| `run_audit` | boolean | `true` | Run npm/pnpm/yarn audit of production deps |
| `audit_level` | string | `critical` | Audit failure level: low, moderate, high, critical |
| `run_codeql` | boolean | `true` | Run CodeQL (javascript-typescript) |
| `build_container` | boolean | `true` | Build/scan/sign the container image after checks |
| `image_name` | string | `''` | Image name (default: repository name) |
| `registry` | string | `''` | Registry prefix (default ghcr.io/<owner>) |
| `context` | string | `''` | Docker build context (default working_directory) |
| `dockerfile` | string | `''` | Dockerfile (default <working_directory>/Dockerfile) |
| `platforms` | string | `linux/amd64,linux/arm64` | Comma-separated image platforms |
| `multiarch_strategy` | string | `native` | native (per-arch runners) or qemu |
| `build_args` | string | `''` | Newline-separated extra build-args |
| `push` | boolean | `true` | Push, attest and sign on non-PR events |
| `trivy_severity` | string | `CRITICAL` | Severities that fail the Trivy scans (image and lockfiles) |
| `trivy_ignore_unfixed` | boolean | `true` | Ignore unfixed vulnerabilities |
| `trivy_ignore_file` | string | `''` | Repo-relative .trivyignore(.yaml) with accepted risks |
| `trivy_fail` | boolean | `true` | Fail on Trivy findings at trivy_severity |

Outputs: `image`, `image_ref`, `image_repo`, `digest`, `image_digest_ref`, `short_sha`

### rust.yaml

| Input | Type | Default | Description |
|---|---|---|---|
| `working_directory` | string | `.` | Crate / workspace directory (Cargo.toml, Cargo.lock, rust-toolchain.toml) |
| `run_fmt` | boolean | `true` | Run cargo fmt --check |
| `run_clippy` | boolean | `true` | Run cargo clippy (warnings are errors) |
| `clippy_args` | string | `--all-targets --all-features --locked -- -D warnings` | cargo clippy arguments |
| `test_args` | string | `--workspace --all-features --locked` | cargo nextest / cargo test arguments |
| `run_deny` | boolean | `true` | Run cargo-deny (licenses only with a deny.toml) |
| `run_audit` | boolean | `true` | Run cargo-audit |
| `run_codeql` | boolean | `true` | Run CodeQL (rust) |
| `build_container` | boolean | `true` | Build/scan/sign the container image after checks |
| `image_name` | string | `''` | Image name (default: repository name) |
| `registry` | string | `''` | Registry prefix (default ghcr.io/<owner>) |
| `context` | string | `''` | Docker build context (default working_directory) |
| `dockerfile` | string | `''` | Dockerfile (default <working_directory>/Dockerfile) |
| `platforms` | string | `linux/amd64,linux/arm64` | Comma-separated image platforms |
| `multiarch_strategy` | string | `native` | native (per-arch runners) or qemu |
| `build_args` | string | `''` | Newline-separated extra build-args |
| `push` | boolean | `true` | Push, attest and sign on non-PR events |
| `trivy_severity` | string | `CRITICAL` | Severities that fail the Trivy scans (image and lockfiles) |
| `trivy_ignore_unfixed` | boolean | `true` | Ignore unfixed vulnerabilities |
| `trivy_ignore_file` | string | `''` | Repo-relative .trivyignore(.yaml) with accepted risks |
| `trivy_fail` | boolean | `true` | Fail on Trivy findings at trivy_severity |

Outputs: `image`, `image_ref`, `image_repo`, `digest`, `image_digest_ref`, `short_sha`

### java.yaml

| Input | Type | Default | Description |
|---|---|---|---|
| `working_directory` | string | `.` | Project directory (pom.xml or build.gradle[.kts]) |
| `build_tool` | string | `auto` | auto, maven or gradle |
| `java_version` | string | `25` | JDK version for setup-java |
| `java_distribution` | string | `temurin` | JDK distribution for setup-java |
| `run_tests` | boolean | `true` | Run tests (JaCoCo coverage) |
| `build_tool_args` | string | `''` | Extra Maven/Gradle arguments for the check build (e.g. -Pci) |
| `native` | boolean | `false` | Quarkus native image (Mandrel, per-arch native build); default Dockerfile becomes <working_directory>/Dockerfile.native |
| `run_osv` | boolean | `true` | Run osv-scanner on the CycloneDX SBOM (gated like Trivy, on CVSS) |
| `run_codeql` | boolean | `true` | Run CodeQL (java-kotlin) |
| `codeql_build_mode` | string | `none` | CodeQL build mode: none (Java) or autobuild (needed for Kotlin) |
| `build_container` | boolean | `true` | Build/scan/sign the container image after checks |
| `image_name` | string | `''` | Image name (default: repository name) |
| `registry` | string | `''` | Registry prefix (default ghcr.io/<owner>) |
| `context` | string | `''` | Docker build context (default working_directory) |
| `dockerfile` | string | `''` | Dockerfile (default <working_directory>/Dockerfile, or Dockerfile.native with native: true) |
| `platforms` | string | `linux/amd64,linux/arm64` | Comma-separated image platforms |
| `multiarch_strategy` | string | `native` | native (per-arch runners) or qemu |
| `build_args` | string | `''` | Newline-separated extra build-args |
| `push` | boolean | `true` | Push, attest and sign on non-PR events |
| `trivy_severity` | string | `CRITICAL` | Severities that fail the Trivy scans (image and lockfiles) |
| `trivy_ignore_unfixed` | boolean | `true` | Ignore unfixed vulnerabilities |
| `trivy_ignore_file` | string | `''` | Repo-relative .trivyignore(.yaml) with accepted risks |
| `trivy_fail` | boolean | `true` | Fail on Trivy findings at trivy_severity |

Outputs: `image`, `image_ref`, `image_repo`, `digest`, `image_digest_ref`, `short_sha`

### workload-bump.yaml

| Input | Type | Default | Description |
|---|---|---|---|
| `image` | string | (required) | Image reference with tag, <repo>:<tag> (stack workflow output `image`) |
| `digest` | string | (required) | Manifest-list digest sha256:... (stack workflow output `digest`; '' skips the bump) |
| `workload_file` | string | `deploy/openchoreo/workload.yaml` | Workload manifest to update |
| `commit_sha` | string | `''` | Source commit written to spec.source.commit (default github.sha) |
| `branch` | string | `''` | Branch to commit to (default: the triggering branch) |
| `commit_message` | string | `''` | Commit message (default 'chore(deploy): bump <image name> image to <tag> [skip ci]') |
| `validate_command` | string | `''` | Optional shell command run after the edit, before committing (e.g. a schema validation) |
| `push` | boolean | `true` | Push the commit (false = dry run: edit, commit locally, show the diff) |

Outputs: `image`, `changed`, `commit_sha`

### nextjs.yaml

| Input | Type | Default | Description |
|---|---|---|---|
| `working_directory` | string | `.` | Directory containing package.json |
| `node_version` | string | `''` | Node.js version (overrides .nvmrc/.node-version/.tool-versions/package.json engines) |
| `run_lint` | boolean | `true` | Run the lint script |
| `run_typecheck` | boolean | `true` | Run the typecheck script (or tsc --noEmit) |
| `run_test` | boolean | `true` | Run the test script |
| `run_audit` | boolean | `true` | Run npm/pnpm/yarn audit of production deps |
| `audit_level` | string | `critical` | Audit failure level: low, moderate, high, critical |
| `run_codeql` | boolean | `true` | Run CodeQL (javascript-typescript) |
| `build_container` | boolean | `true` | Build/scan/sign the container image after checks |
| `image_name` | string | `''` | Image name (default: repository name) |
| `registry` | string | `''` | Registry prefix (default ghcr.io/<owner>) |
| `context` | string | `''` | Docker build context (default working_directory) |
| `dockerfile` | string | `''` | Dockerfile (default <working_directory>/Dockerfile) |
| `platforms` | string | `linux/amd64,linux/arm64` | Comma-separated image platforms |
| `multiarch_strategy` | string | `native` | native (per-arch runners) or qemu |
| `build_args` | string | `''` | Newline-separated extra build-args |
| `push` | boolean | `true` | Push, attest and sign on non-PR events |
| `trivy_severity` | string | `CRITICAL` | Severities that fail the Trivy scans (image and lockfiles) |
| `trivy_ignore_unfixed` | boolean | `true` | Ignore unfixed vulnerabilities |
| `trivy_ignore_file` | string | `''` | Repo-relative .trivyignore(.yaml) with accepted risks |
| `trivy_fail` | boolean | `true` | Fail on Trivy findings at trivy_severity |

Outputs: `image`, `image_ref`, `image_repo`, `digest`, `image_digest_ref`, `short_sha`

### elixir.yaml

| Input | Type | Default | Description |
|---|---|---|---|
| `working_directory` | string | `.` | Directory containing mix.exs |
| `otp_version` | string | `''` | OTP version (default: from .tool-versions) |
| `elixir_version` | string | `''` | Elixir version (default: from .tool-versions) |
| `postgres` | boolean | `false` | Start a Postgres service for tests (DATABASE_URL, PG* env are set) |
| `postgres_image` | string | `postgres:17` | Postgres service image |
| `run_credo` | boolean | `true` | Run credo (only if it is a dependency) |
| `run_sobelow` | boolean | `true` | Run sobelow (only if it is a dependency) |
| `test_args` | string | `''` | Extra mix test arguments |
| `build_container` | boolean | `true` | Build/scan/sign the container image after checks |
| `image_name` | string | `''` | Image name (default: repository name) |
| `registry` | string | `''` | Registry prefix (default ghcr.io/<owner>) |
| `context` | string | `''` | Docker build context (default working_directory) |
| `dockerfile` | string | `''` | Dockerfile (default <working_directory>/Dockerfile) |
| `platforms` | string | `linux/amd64,linux/arm64` | Comma-separated image platforms |
| `multiarch_strategy` | string | `native` | native (per-arch runners) or qemu |
| `build_args` | string | `''` | Newline-separated extra build-args |
| `push` | boolean | `true` | Push, attest and sign on non-PR events |
| `trivy_severity` | string | `CRITICAL` | Severities that fail the Trivy scans (image and lockfiles) |
| `trivy_ignore_unfixed` | boolean | `true` | Ignore unfixed vulnerabilities |
| `trivy_ignore_file` | string | `''` | Repo-relative .trivyignore(.yaml) with accepted risks |
| `trivy_fail` | boolean | `true` | Fail on Trivy findings at trivy_severity |

Outputs: `image`, `image_ref`, `image_repo`, `digest`, `image_digest_ref`, `short_sha`

### ruby.yaml

| Input | Type | Default | Description |
|---|---|---|---|
| `working_directory` | string | `.` | Directory containing Gemfile |
| `ruby_version` | string | `''` | Ruby version (default: .ruby-version / .tool-versions) |
| `test_command` | string | `auto` | Test command; 'auto' = rspec / bin/rails test / rake test; 'none' skips |
| `run_rubocop` | boolean | `true` | Run rubocop (only if bundled) |
| `run_brakeman` | string | `auto` | Run brakeman: 'auto' (Rails apps), 'true' or 'false' |
| `postgres` | boolean | `false` | Start a Postgres service for tests (DATABASE_URL, PG* env are set) |
| `postgres_image` | string | `postgres:17` | Postgres service image |
| `run_codeql` | boolean | `true` | Run CodeQL (ruby) |
| `build_container` | boolean | `true` | Build/scan/sign the container image after checks |
| `image_name` | string | `''` | Image name (default: repository name) |
| `registry` | string | `''` | Registry prefix (default ghcr.io/<owner>) |
| `context` | string | `''` | Docker build context (default working_directory) |
| `dockerfile` | string | `''` | Dockerfile (default <working_directory>/Dockerfile) |
| `platforms` | string | `linux/amd64,linux/arm64` | Comma-separated image platforms |
| `multiarch_strategy` | string | `native` | native (per-arch runners) or qemu |
| `build_args` | string | `''` | Newline-separated extra build-args |
| `push` | boolean | `true` | Push, attest and sign on non-PR events |
| `trivy_severity` | string | `CRITICAL` | Severities that fail the Trivy scans (image and lockfiles) |
| `trivy_ignore_unfixed` | boolean | `true` | Ignore unfixed vulnerabilities |
| `trivy_ignore_file` | string | `''` | Repo-relative .trivyignore(.yaml) with accepted risks |
| `trivy_fail` | boolean | `true` | Fail on Trivy findings at trivy_severity |

Outputs: `image`, `image_ref`, `image_repo`, `digest`, `image_digest_ref`, `short_sha`

### helm-chart.yaml

| Input | Type | Default | Description |
|---|---|---|---|
| `chart_path` | string | `.` | Chart directory |
| `chart_version` | string | `''` | Chart version override |
| `app_version` | string | `''` | appVersion override |
| `lint_args` | string | `''` | Extra helm lint arguments |
| `helm_version` | string | `latest` | Helm version for azure/setup-helm |
| `registry` | string | `''` | OCI registry prefix for charts (default ghcr.io/<owner>/charts) |
| `push` | boolean | `true` | Push and sign on non-PR events |

Outputs: `chart`, `digest`, `chart_digest_ref`

### crossplane-configuration.yaml

| Input | Type | Default | Description |
|---|---|---|---|
| `package_root` | string | `.` | Directory containing crossplane.yaml |
| `examples_dir` | string | `examples` | Example XRs (relative to package_root); bundled into the package |
| `render_dir` | string | `tests/render` | Render test assets relative to package_root (functions.yaml, expected/, observed/, extra-resources/) |
| `ignore` | string | `''` | Extra comma-separated xpkg build --ignore patterns |
| `crossplane_version` | string | `v2.5.0` | Crossplane CLI version |
| `package_name` | string | `''` | Package (OCI repository) name (default: metadata.name in crossplane.yaml) |
| `registry` | string | `''` | Registry prefix (default ghcr.io/<owner>) |
| `push` | boolean | `true` | Push and sign on non-PR events |

Outputs: `package`, `digest`, `package_digest_ref`

### crossplane-provider.yaml

| Input | Type | Default | Description |
|---|---|---|---|
| `working_directory` | string | `.` | Provider repository root (go.mod, Makefile) |
| `package_root` | string | `package` | Directory with crossplane.yaml + crds, relative to working_directory |
| `generate_command` | string | `make generate` | Code generation command checked for a clean git diff ('' skips) |
| `run_lint` | boolean | `true` | Run golangci-lint |
| `run_vulncheck` | boolean | `true` | Run govulncheck |
| `run_codeql` | boolean | `false` | Run CodeQL (go); slow on large generated upjet providers |
| `go_test_flags` | string | `-race -coverprofile=coverage.out -covermode=atomic ./...` | go test flags |
| `crossplane_version` | string | `v2.5.0` | Crossplane CLI version |
| `package_name` | string | `''` | Package (OCI repository) name (default: metadata.name in crossplane.yaml) |
| `controller_image_name` | string | `''` | Controller image name (default <package_name>-controller) |
| `registry` | string | `''` | Registry prefix (default ghcr.io/<owner>) |
| `dockerfile` | string | `''` | Controller Dockerfile (default <working_directory>/Dockerfile) |
| `platforms` | string | `linux/amd64,linux/arm64` | Comma-separated platforms (controller image and package) |
| `multiarch_strategy` | string | `native` | native (per-arch runners) or qemu |
| `push` | boolean | `true` | Push and sign on non-PR events |
| `trivy_severity` | string | `CRITICAL` | Severities that fail the controller image scan |

Outputs: `package`, `digest`, `package_digest_ref`, `controller_image_digest_ref`

