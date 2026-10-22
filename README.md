# RAG chatbot with Spring Boot and Kong

Two interchangeable development stacks expose the same Kotlin/Spring Boot API:

| Mode | Gateway | Retrieval | Models | Account required |
|---|---|---|---|---|
| `local` (default) | Free OSS Kong, DB-less HTTP proxy | Spring Boot chunks documents, embeds and searches an in-memory vector index | Local Ollama | No |
| `konnect` | Self-managed Kong Enterprise data plane, managed by Konnect | Kong AI RAG Injector and Redis Stack | OpenAI through Kong AI Proxy | Konnect, appropriate AI Gateway entitlement, OpenAI |

Local mode deliberately uses **ordinary Kong proxy routes**, not proprietary AI plugins. It is a real embedding/retrieval/generation flow, not a mock. Konnect mode keeps retrieval and model credentials in Kong; Spring only forwards chat requests and supplies system instructions.

```text
Local:
  Client -> Spring Boot -> Kong OSS -> Ollama chat model
              |               |
              +-> embeddings -+-> Ollama embedding model
              +-> in-memory vector search over knowledge/*.md and *.txt

Konnect:
  Client -> Spring Boot -> Kong data plane -> AI Proxy -> OpenAI
                               |
                               +-> AI RAG Injector -> Redis vector index
                               ^
                         Konnect control plane (mTLS)
```

## What was missing

The original repository provided a Spring-to-Kong integration and containers, but not a runnable RAG system: there was no document ingestion, index initialization, model provisioning, or gateway route/plugin provisioning. It also required external Konnect setup for every local run, and its Java 21 Docker images could not compile the Java 25 application.

The local stack now provisions its routes, downloads models, indexes sample documents and waits for API readiness. The Konnect bootstrap automates the remote configuration and local certificate/environment generation; ingestion is a separate explicit operation because it sends knowledge documents to the configured external embedding provider.

## Start locally

Install Docker with Compose v2, `make` and `curl`. No host JVM, Maven, Terraform, account, API key or Kong license is needed for Compose. Allow several GB of disk and memory for the images/models; Docker runs Ollama on CPU by default, including on macOS. First startup downloads models and can take several minutes.

```bash
make up
make smoke       # requires jq; exercises RAG, support, alias and invalid input
make logs
make down        # preserves downloaded models
```

`make up` creates a private `.env` only if absent. Defaults are `qwen2.5:1.5b` for chat and `nomic-embed-text` for embeddings. Override `LOCAL_CHAT_MODEL` and `LOCAL_EMBEDDING_MODEL` in `.env` before starting. Different embedding models require rebuilding the index, which happens automatically on application startup.

The API listens at `http://127.0.0.1:8080`, Kong at `http://127.0.0.1:8000`. Ollama is private to the Docker network; Kong's Admin API is disabled. Only loopback ports are published. `/health` reports application readiness, including completed local indexing, not end-to-end provider availability.

```bash
curl --fail-with-body http://127.0.0.1:8080/api/rag/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"What is the project release checklist?"}'
```

| Endpoint | Purpose |
|---|---|
| `POST /api/rag/chat` | Grounded answers |
| `POST /api/support/chat` | Grounded answers with a conservative support policy |
| `POST /api/chat` | Compatibility alias for RAG |
| `GET /health` | Application readiness |

Chat requests use `{"message":"..."}` and responses use `{"response":"..."}`. Messages must contain 1-8,000 characters. Model/gateway failures return HTTP 502.

### Your own knowledge

Place UTF-8 Markdown/text files in `knowledge/`, then run `make restart`. Files are mounted read-only; local embeddings and the index are rebuilt on startup. Local mode fails startup explicitly if knowledge cannot be indexed. It does not silently downgrade to an ungrounded chatbot.

The in-memory index is intentionally a small-corpus development implementation, not a multi-tenant production store. Source titles are included in context so the model can cite them. Similarity thresholds are heuristics, not guarantees of answer correctness or resistance to prompt injection. Small local models can still hallucinate.

Useful application settings are `RAG_TOP_K`, `RAG_MIN_SCORE`, `RAG_DOCUMENTS_PATH`, `RAG_EMBEDDING_MODEL`, `KONG_EMBEDDINGS_ROUTE`, `KONG_CONNECT_TIMEOUT`, and `KONG_READ_TIMEOUT`. Container settings belong in the Compose environment block (or its Terraform equivalent); arbitrary `.env` values are not automatically forwarded to the JVM.

## Switch modes

```bash
make MODE=konnect switch    # after Konnect bootstrap below
make MODE=local switch
```

`switch` stops the other **Compose** stack before starting the selected stack. It retains both modes' named volumes. `MODE` applies to `up`, `down`, `logs`, `ps`, `config`, `build`, and Terraform targets. Local settings use `.env`; Konnect uses `.env.konnect`. Both stacks bind the same host ports and must not run simultaneously.

Do not mix Compose and Terraform deployments on the same ports. Stop the current deployment using the tool that created it before changing tools. `docker compose down -v` and `terraform destroy` delete managed volumes and their data; ordinary `make down` does not.

## Konnect mode

Konnect and the model provider remain external managed services. Bootstrap requires `curl`, `jq`, OpenSSL, a Konnect personal access token with control-plane configuration permissions, and an OpenAI API key. Use a **dedicated** compatible hybrid control plane; bootstrap manages project-named services/routes/plugins, not an entire organization.

Provider credentials are sent only to your selected Konnect regional API and stored in Kong configuration; never put them in source control. Knowledge documents are sent to the external embedding provider during ingestion and as retrieved context during generation. Use only data approved for those services.

The exact bootstrap and ingestion steps and Kong references are documented below.

```bash
# Create a dedicated hybrid control plane in Konnect first.
export KONNECT_REGION=eu                 # us, eu, au, in, me or sg
export KONNECT_CONTROL_PLANE_ID=...      # control-plane UUID
export KONNECT_TOKEN=...                 # PAT, not committed or saved
export OPENAI_API_KEY=...                # stored in Kong configuration
make konnect-bootstrap
make MODE=konnect switch

# Only needed for the temporary, standalone ingestion worker:
export KONG_LICENSE_DATA='...'           # JSON AI Gateway Enterprise license
make konnect-ingest
make smoke
```

Bootstrap reads the control plane's real connection/SNI hostnames, registers the public node certificate (the private key stays local), and upserts only the project-named service/routes and its AI Proxy Advanced/RAG Injector plugins. Re-running bootstrap updates configuration and reuses the Redis password. It generates private `.env.konnect`, `terraform/konnect.tfvars` and `secrets/` configuration. Rotate the self-signed node certificate before its one-year expiry. Match `KONG_GATEWAY_IMAGE` to a version supported by your control plane; the documented Enterprise default is `3.16.0.1`. OSS is separately pinned to `3.9.4`.

**Ingestion is deliberately not sent to a made-up Konnect API.** Kong documents `POST /ai-rag-injector/{plugin_id}/ingest_chunk` on the traditional Admin API, and its ingestion tutorial is marked on-prem only. Therefore `make konnect-ingest` starts a temporary **standalone Enterprise** worker with PostgreSQL on the Konnect stack's private network, using the same plugin ID, namespace, embedding model and Redis as the Konnect-managed data plane. Its Admin API is bound to a random loopback port and its proxy is disabled. Both temporary containers are removed on exit. This works with either the Compose or Terraform Konnect stack and never starts in local OSS mode.

That worker requires a **standalone AI Gateway Enterprise license**; do not assume a Konnect subscription also licenses standalone nodes. If your organization cannot provide one, use Kong's supported ingestion infrastructure for that account or use the fully local mode. No license/token is bundled. The Enterprise workflow cannot be exercised end-to-end without these external credentials and entitlements.

Documents are chunked before ingestion; requests include the source file name. The shared namespace is `kong_chatbot_v1`, embeddings use `text-embedding-3-large` (3,072 dimensions), and embedding/vector failures stop requests rather than silently dropping RAG. Re-running ingestion **adds** chunks, so avoid repeatedly ingesting unchanged documents. For changed or removed documents, deliberately clear/recreate the development Redis volume and ingest the complete corpus; this deletes all knowledge in that volume. The temporary worker has no chat traffic and is not the Konnect data plane.

`secrets/konnect-rag-plugin.json` contains the provider key, `secrets/kong-license.json` contains the worker license, and `.env.konnect` contains the Redis password. All are git-ignored and created with owner-only permissions. Delete/rotate them according to your organization's policy.

### Official Kong references

The configuration follows Kong's published sources, with OSS and Enterprise kept separate:

- [OSS 3.9.4 release](https://github.com/Kong/kong/releases/tag/3.9.4) and [DB-less declarative configuration](https://developer.konghq.com/gateway/db-less-mode/).
- [Gateway Docker installation](https://developer.konghq.com/gateway/install/docker/) and [version support policy](https://developer.konghq.com/gateway/version-support-policy/) (3.14 is the LTS family; select an appropriate current patch if your organization standardizes on LTS).
- [AI RAG Injector requirements and Redis modules](https://developer.konghq.com/plugins/ai-rag-injector/), [configuration](https://developer.konghq.com/plugins/ai-rag-injector/reference/), [Admin ingestion API](https://developer.konghq.com/plugins/ai-rag-injector/api/) and [official on-prem ingestion example](https://developer.konghq.com/ai-gateway/v1/how-to/use-ai-rag-injector-plugin/).
- [Konnect control-plane API source](https://github.com/Kong/developer.konghq.com/blob/main/api-specs/konnect/control-planes/v2/openapi.yaml) and [core-entity API source](https://github.com/Kong/developer.konghq.com/blob/main/api-specs/konnect/control-planes-config/v2/openapi.yaml).

## Terraform deployment

The Terraform root deploys to the **local Docker daemon**, not AWS, Azure or another cloud. Cloud deployment still needs a chosen platform, networking, persistent storage, a registry and platform-specific Terraform resources.

Install Terraform 1.5+ and Docker with Buildx. The Make targets automatically pass the active Docker context's endpoint and Buildx builder to the Terraform Docker provider, which otherwise defaults to `/var/run/docker.sock` and its legacy builder. They respect explicit `DOCKER_HOST` and `TF_VAR_docker_builder` overrides. If running Terraform directly instead of through Make, set those variables yourself so the provider and CLI target the same daemon/builder.

```bash
make terraform-plan
make terraform-up
make smoke
make terraform-down
```

Local is the default and requires no certificate or remote credentials. Terraform builds the Java 25 image, starts Ollama and Kong, downloads both models, then starts Spring. `make terraform-up` also waits for API readiness after apply; a raw `terraform apply` does not.

For Konnect, first bootstrap, then:

```bash
make MODE=konnect terraform-plan
make MODE=konnect terraform-up
make konnect-ingest
make smoke
make MODE=konnect terraform-down
```

Bootstrap generates a private `terraform/konnect.tfvars` containing the endpoints and Redis password. Terraform state also contains the Redis password; secure and back up the state. No provider API key is written to Terraform state by these Docker resources. Switching Terraform's `mode` replaces the mode-specific containers but retains model/index volumes until destroy.

## Host development

With Kong and Ollama running from the local Compose stack, run Spring on the host instead of the API container:

```bash
docker compose -f compose.local.yaml stop chatbot
RAG_MODE=local KONG_MODEL=qwen2.5:1.5b KONG_READ_TIMEOUT=180s \
  mvn spring-boot:run
```

This requires JDK 25 and Maven. The default host document directory is `knowledge/`; default gateway URL is `http://localhost:8000`. `mvn test` runs the application tests.

## Production boundaries

This is a local development/reference deployment, not a production platform. Before exposure, add identity/session authorization, tenant-scoped retrieval, knowledge access controls, conversation retention, tracing/monitoring, backup/restore, secret management, TLS and capacity planning. System instructions are defense in depth, **not** a security boundary. The support instructions do not implement a moderation/guardrail plugin.
