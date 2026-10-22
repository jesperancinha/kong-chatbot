# Local retrieval mode

Local mode reads approved Markdown and plain text documents from the configured
read-only knowledge directory at startup. It chunks the documents and sends
embedding requests through Kong to Ollama using nomic-embed-text by default.
The local generation model is qwen2.5:1.5b, configured with KONG_MODEL.

The vector index is in memory and is intended for local development, not
production-scale storage. Documents persist in the mounted knowledge volume.
Restart the application after changing documents; it rebuilds and reembeds the
entire index on every restart. An empty directory or unavailable embeddings
prevents startup. Both chat modes use approved retrieved excerpts and cite
source titles. If no excerpt meets the similarity threshold, the application
returns that it does not know without calling the generation model.

Provider credentials belong in Kong, never in this application.
