FROM debian:bookworm-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251 AS runtime-base

ARG TARGETARCH
ARG YQ_VERSION=4.53.6
ARG BASH_PACKAGE_VERSION=5.2.15-2+b13
ARG CA_CERTIFICATES_PACKAGE_VERSION=20250419~deb12u1
ARG CURL_PACKAGE_VERSION=7.88.1-10+deb12u15
ARG JQ_PACKAGE_VERSION=1.6-2.1+deb12u2
ARG SOCAT_PACKAGE_VERSION=1.7.4.4-2

RUN apt-get update \
	&& apt-get install --yes --no-install-recommends \
		bash="${BASH_PACKAGE_VERSION}" \
		ca-certificates="${CA_CERTIFICATES_PACKAGE_VERSION}" \
		curl="${CURL_PACKAGE_VERSION}" \
		jq="${JQ_PACKAGE_VERSION}" \
		socat="${SOCAT_PACKAGE_VERSION}" \
	&& rm -rf /var/lib/apt/lists/* \
	&& case "$TARGETARCH" in \
		amd64) yq_sha256='c5f056448f973ae7d39b5401949648a78f2dc1947d6a8eb65be60d5c504b9385' ;; \
		arm64) yq_sha256='88a1016bc1d657375a35864e4f44b6f333df8ff97b559f51bba0adcb2169df09' ;; \
		*) printf 'Unsupported architecture: %s\n' "$TARGETARCH" >&2; exit 1 ;; \
	esac \
	&& curl --fail --location --silent --show-error \
		"https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${TARGETARCH}" \
		--output /tmp/yq \
	&& printf '%s  %s\n' "$yq_sha256" /tmp/yq | sha256sum --check --strict \
	&& install --mode=0755 /tmp/yq /usr/local/bin/yq \
	&& rm /tmp/yq \
	&& useradd --create-home --uid 10001 sandbox

WORKDIR /workspace

FROM runtime-base AS runtime

COPY --chown=sandbox:sandbox --chmod=0555 bin/bash-http bin/bash-http
COPY --chown=sandbox:sandbox handlers/ handlers/
COPY --chown=sandbox:sandbox lib/ lib/
COPY --chown=sandbox:sandbox openapi.yaml ./

USER sandbox

EXPOSE 8080

ENTRYPOINT ["./bin/bash-http"]
CMD ["serve", "openapi.yaml", "--host", "0.0.0.0", "--port", "8080"]

FROM runtime-base AS test

ARG MAKE_PACKAGE_VERSION=4.3-4.1
ARG SHELLCHECK_PACKAGE_VERSION=0.9.0-1
ARG SHFMT_PACKAGE_VERSION=3.6.0-1+b2

USER root
RUN apt-get update \
	&& apt-get install --yes --no-install-recommends \
		make="${MAKE_PACKAGE_VERSION}" \
		shellcheck="${SHELLCHECK_PACKAGE_VERSION}" \
		shfmt="${SHFMT_PACKAGE_VERSION}" \
	&& rm -rf /var/lib/apt/lists/*

COPY --chown=sandbox:sandbox . .

USER sandbox

CMD ["make", "check"]
