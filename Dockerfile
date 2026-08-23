FROM python:3.11-slim AS builder

# Pinned Hermes release on UPSTREAM NousResearch/hermes-agent.
# fcbd107 = v2026.8.19 (v0.20.5). We no longer track the yulonghe97 fork:
# 3 of its 4 patches are already upstream; the 4th (send_message
# edit/delete for Slack) is re-applied below via patches/. To upgrade,
# bump this to a newer upstream commit and re-verify the patch applies.
# Override at build time: `docker build --build-arg HERMES_GIT_REF=...`.
ARG HERMES_GIT_REF=fcbd1076a93841fa88855acce810e342a5b78101

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
# `git clone --branch` won't accept a bare SHA, so fetch-then-checkout.
# `--filter=blob:none` keeps the clone small without the hard depth=1
# limit that would prevent a non-tip SHA from being resolvable.
RUN git clone --filter=blob:none --no-checkout --recurse-submodules https://github.com/NousResearch/hermes-agent.git \
  && cd hermes-agent \
  && git checkout "${HERMES_GIT_REF}" \
  && git submodule update --init --recursive

# Re-apply our one carried patch: send_message action=edit/delete for Slack.
# The other 3 legacy fork patches are already in upstream. This is pinned to
# ${HERMES_GIT_REF}; on any pin bump, re-verify the patch still applies.
COPY patches/ /opt/patches/
RUN cd /opt/hermes-agent && git apply --verbose /opt/patches/0001-send-message-edit-delete.patch

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

RUN pip install --no-cache-dir --upgrade pip setuptools wheel
RUN pip install --no-cache-dir -e "/opt/hermes-agent[messaging,cron,cli,pty,mcp]"


FROM python:3.11-slim

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    openssh-client \
    tini \
  && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/venv/bin:${PATH}" \
  PYTHONUNBUFFERED=1 \
  HERMES_HOME=/data/.hermes \
  HOME=/data

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /opt/hermes-agent /opt/hermes-agent

WORKDIR /app
COPY scripts/entrypoint.sh /app/scripts/entrypoint.sh
RUN chmod +x /app/scripts/entrypoint.sh

ENTRYPOINT ["tini", "--"]
CMD ["/app/scripts/entrypoint.sh"]
