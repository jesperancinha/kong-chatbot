# Kong Chatbot Architecture — 10-slide presentation

## Intro

SOFTWARE ENGINEERING · AI · KNOWLEDGE SHARING
João Esperancinha
Building reliable software, exploring AI, and sharing what I learn.

Technical expertise
Kotlin & Java
Spring Boot
Distributed systems
APIs & Kong Gateway
Cloud & AWS
Generative AI & RAG

Knowledge sharing — JESPROTECH

Practical programming tutorials, technical quizzes, software architecture, Kotlin and Java, and emerging AI engineering practices.

20 years of IT experience · Engineering, integration, architecture, and mentoring

## Slide 1 — RAG: give an LLM relevant knowledge

- **Retrieval-Augmented Generation (RAG)** finds relevant passages in a knowledge
  source and supplies them to a language model along with the user's question.
- The model can answer from project-specific material that was not part of its
  original training data.
- In this project, the knowledge source is the Markdown and text files under
  `knowledge/`.
- The goal is a more useful, evidence-grounded answer—not a guarantee that the
  model will always be correct.

**Presenter note:** RAG connects a model's language-generation ability to a
maintained, task-specific knowledge base. It is especially useful when answers
must reflect current or organization-specific documentation.

## Slide 2 — The RAG cycle: retrieve, ground, generate

1. **Prepare:** split documents into overlapping chunks and calculate an
   embedding vector for each chunk.
2. **Retrieve:** embed the incoming question and rank document chunks by vector
   similarity.
3. **Ground:** include the best matching excerpts and their source titles in
   the model request.
4. **Generate:** ask the model to answer from those excerpts and cite relevant
   source titles.
- Local mode returns “I don't know” when no passage meets its configured
  threshold; it does not call the generation model for an empty result.
- Konnect mode uses the AI RAG Injector plugin to retrieve and inject context.

**Presenter note:** Similarity thresholds are heuristics. Grounding improves
traceability, but it does not itself establish factual correctness or prevent
prompt injection.

## Slide 3 — One chatbot API, two deployment modes

```text
Client
  |
  v
Spring Boot API (:8080)
  |                                |
  | LOCAL                          | KONNECT
  v                                v
Kong OSS (:8000)             Kong Gateway data plane (:8000)
  |                          connected to Konnect control plane
  +--> Ollama chat model            |
  +--> Ollama embeddings            +--> AI RAG Injector
  |       ^                          |       |
  |       |                          |       v
  +-- Spring in-memory index     Redis Stack vector index
                                     |
                                     +--> AI Proxy --> OpenAI
```

- Both modes expose the Spring API; `RAG_MODE` selects where retrieval happens.
- Local mode is designed for development without a Kong account or external
  model credentials.
- Konnect mode moves retrieval and model-provider integration into Kong's
  configured AI Gateway plugins.
- Compose and Terraform in this repository run on a local Docker environment;
  Terraform is not currently a cloud-platform deployment.

**Presenter note:** The two paths are alternatives, not consecutive stages.
Local OSS uses ordinary proxy routes. Konnect mode connects a self-managed
Kong data plane to a Konnect control plane.

## Slide 4 — Kong Gateway: the model-traffic boundary

- Spring sends chat-completion requests to Kong through configured routes; the
  application does not call the model provider directly.
- In local mode, **Kong OSS** proxies chat and embedding HTTP requests to Ollama
  using declarative, DB-less configuration in `kong/local.yaml`.
- In Konnect mode, **Kong Gateway** routes traffic through the configured
  AI Proxy Advanced and AI RAG Injector plugins.
- The gateway is a natural place to centralize provider connectivity,
  credentials, routing, and AI policies as the platform evolves.
- Local mode deliberately avoids paid/proprietary AI plugins.

**Presenter note:** The local proxy is real Kong traffic routing, but local
retrieval is implemented in Spring. Do not describe the OSS configuration as
having the Konnect AI plugins enabled.

## Slide 5 — Kong Konnect: centrally managed gateway configuration

- **Konnect control plane:** manages configuration for the connected Kong data
  plane; it is separate from the request-serving data plane.
- The bootstrap script registers the data-plane client certificate and
  upserts this project's OpenAI service, RAG/support routes, AI Proxy Advanced
  plugin, and AI RAG Injector plugin.
- The configured RAG plugin uses OpenAI embeddings and a Redis Stack vector
  index; the AI Proxy sends grounded chat requests to the configured OpenAI
  model.
- This separates Spring's API/orchestration responsibilities from gateway
  policy and provider integration.
- This mode requires a compatible Konnect account/entitlement and OpenAI
  credentials. Document ingestion is an explicit operation and has additional
  standalone Enterprise licensing requirements in this setup.

**Presenter note:** Bootstrap automates project-scoped Konnect configuration;
it is not a substitute for account setup, licensing, approved data handling,
or credential management.

## Slide 6 — Spring Boot: API and application orchestration

- The Kotlin/Spring Boot application exposes `POST /api/rag/chat`,
  `POST /api/support/chat`, the compatibility alias `POST /api/chat`, and
  `GET /health`.
- `ChatController` handles HTTP requests; `ChatService` selects the RAG or
  support instructions and calls the gateway client.
- `KongAiGatewayClient` handles the HTTP request to Kong and reports gateway
  failures rather than silently returning an empty answer.
- Local mode adds startup indexing and question-time retrieval through a
  `KnowledgeContextProvider`; gateway mode delegates retrieval to Kong.
- The application enforces request validation and includes source titles in
  locally retrieved context.

**Presenter note:** Spring is the stable application-facing API and
orchestration layer. The retrieval provider is mode-dependent, so the same
chat API can work with either retrieval implementation.

## Slide 7 — Local mode: end-to-end RAG without external accounts

- Markdown/text files are mounted read-only from `knowledge/`.
- At startup, Spring chunks and embeds the documents through Kong's embedding
  route to Ollama, then builds an in-memory vector index.
- For each question, Spring embeds the query, ranks passages by cosine
  similarity, and supplies the best matches to Kong's chat route.
- Kong proxies to the local Ollama chat model; the answer can cite the source
  document title.
- An unavailable/empty knowledge corpus or failed embedding prevents startup;
  the vector index is intentionally not a persistent, production-scale store.

**Presenter note:** `make up` starts the local stack and provisions its models;
`make smoke` exercises representative requests. Restarting the app rebuilds
and re-embeds the local index.

## Slide 8 — Infrastructure as Code: repeatable environments

- Compose files describe local and Konnect container stacks; `kong/local.yaml`
  describes the local gateway routes.
- Terraform declares Docker networks, images, containers, volumes, ports, and
  mode-specific configuration in `terraform/`.
- The `local`/`konnect` variable selects which resources and settings are
  provisioned; `terraform plan` previews changes before apply.
- Declarative configuration makes setup reproducible, reviewable, and easier
  to change consistently than manual container and gateway setup.
- `make terraform-up` applies the configuration and waits for API readiness;
  `make terraform-down` removes Terraform-managed resources.

**Presenter note:** IaC makes the implemented local Docker setup repeatable,
but does not automatically make it production-ready. The current Terraform
provider targets Docker; cloud infrastructure would need a chosen platform
and corresponding resources.

## Slide 9 — Operations, trust boundaries, and production gaps

- Local published ports bind to loopback; Kong's Admin API and the Redis
  service are not published to the host in the provided stacks.
- Konnect mode sends provider credentials to Kong configuration and sends
  documents to the external embedding provider during ingestion. Only use
  data approved for those services.
- Keep generated credentials, certificates, and Terraform state private;
  Terraform state contains the Redis password.
- This is a development/reference deployment. Before exposing it, add
  authentication/authorization, tenant-scoped retrieval, access controls,
  TLS, secret management, monitoring, backups, retention policy, and
  capacity planning.
- System instructions and similarity thresholds are not security boundaries;
  the support prompt is not a moderation/guardrail plugin.

**Presenter note:** The project deliberately documents its production
boundaries. A successful local smoke test demonstrates a working path, not
production security, availability, or answer quality.

## Slide 10 — Takeaways and a practical walkthrough

- **RAG** supplies relevant project knowledge to model requests and makes
  answers easier to ground in named sources.
- **Kong Gateway** is the shared traffic boundary; **Konnect** adds centrally
  managed configuration and AI Gateway plugins for the managed retrieval path.
- **Spring Boot** owns the stable API and coordinates chat behavior while
  supporting either local or gateway-managed retrieval.
- **Infrastructure as Code** captures the repeatable development deployment;
  production deployment still requires platform-specific design and controls.
- Suggested demo: start with `make up`, ask about the release checklist via
  `POST /api/rag/chat`, then contrast the local and Konnect architecture.
- Sample request: `{"message":"What is the project release checklist?"}`

**Presenter note:** Close by highlighting the architecture's central design
choice: keep the client API consistent while making retrieval and model
connectivity selectable by deployment mode.

---

**Project references:** `README.md`, `knowledge/local-mode.md`,
`src/main/kotlin/org/jesperancinha/kong/chatbot/`,
`compose.local.yaml`, `compose.yaml`, `kong/local.yaml`, `terraform/`,
and `scripts/configure-konnect.sh`.

## End

Build a RAG Chatbot with Kong AI Gateway
Explore the project behind this presentation.
- Retrieval-Augmented Generation (RAG)
- Application and gateway integration
- Kotlin and Spring Boot
- Practical implementation and deployment

Explore the code on GitHub

https://github.com/jesperancinha/kong-chatbot
