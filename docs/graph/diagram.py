from diagrams import Cluster, Diagram, Edge
from diagrams.gcp.compute import Run
from diagrams.gcp.operations import Logging
from diagrams.gcp.security import SecretManager
from diagrams.gcp.storage import Storage
from diagrams.generic.compute import Rack
from diagrams.generic.network import Firewall
from diagrams.onprem.client import Users
from diagrams.onprem.database import PostgreSQL

graph_attr = {
    "fontsize": "18",
    "pad": "0.5",
    "nodesep": "0.7",
    "ranksep": "1.2",
}

with Diagram(
    "Focus Link Infrastructure Architecture",
    filename="tkb_architecture",
    outformat=["png", "svg"],
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    client = Users("iPhone / Desktop")

    with Cluster("Cloudflare"):
        cloudflare = Firewall("DNS / WAF / Proxy")

    with Cluster("Google Cloud - TKB Project"):
        api = Run("Go API\nConnect RPC")
        secrets = SecretManager("Secrets")
        logging = Logging("Logs")
        artifacts = Storage("Artifact Registry\n(placeholder icon)")

    with Cluster("Supabase"):
        auth = Rack("Supabase Auth")
        pooler = Rack("Transaction Pooler")
        db = PostgreSQL("PostgreSQL\napp schema")

    client >> Edge(label="HTTPS + JWT") >> cloudflare
    cloudflare >> api

    client >> Edge(label="Login") >> auth
    api >> Edge(label="JWKS") >> auth

    api >> Edge(label="SQL / TLS") >> pooler
    pooler >> db

    api >> Edge(style="dashed") >> secrets
    api >> Edge(style="dashed") >> logging
    artifacts >> Edge(style="dashed", label="Image") >> api
