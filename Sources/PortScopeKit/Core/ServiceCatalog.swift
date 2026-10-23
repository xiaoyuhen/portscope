import Foundation

/// The built-in knowledge base.
///
/// Every entry is a claim with a confidence, not a guess dressed as a fact.
/// Entries are ordered strongest-first within each category, and the identifier
/// takes the first process match, then falls back to HTTP headers, then to
/// well-known ports.
public enum ServiceCatalog {
    // MARK: - Process fingerprints

    public static let processFingerprints: [ProcessFingerprint] = [
        // --- JavaScript / TypeScript ---
        ProcessFingerprint(
            any: [.argumentBasename("vite"), .argumentBasename("vite.js")],
            match(kind: .devServer, title: "Vite", summary: "service.vite", confidence: 0.95)
        ),
        ProcessFingerprint(
            any: [.argumentPathSuffix("node_modules/vite/bin/vite.js")],
            match(kind: .devServer, title: "Vite", summary: "service.vite", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.argumentBasename("next"), .argumentContains("next dev")],
            match(kind: .devServer, title: "Next.js", summary: "service.next", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.argumentContains("next-server")],
            match(kind: .devServer, title: "Next.js", summary: "service.next", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.argumentBasename("nuxt"), .argumentContains("nuxt dev")],
            match(kind: .devServer, title: "Nuxt", summary: "service.nuxt", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.argumentContains("webpack"), .argumentBasename("webpack-dev-server")],
            match(kind: .bundler, title: "webpack", summary: "service.webpack", confidence: 0.85)
        ),
        ProcessFingerprint(
            any: [.argumentBasename("nodemon")],
            match(kind: .devServer, title: "nodemon", summary: "service.nodemon", confidence: 0.8)
        ),
        ProcessFingerprint(
            any: [.argumentContains("react-scripts")],
            match(kind: .devServer, title: "Create React App", summary: "service.cra", confidence: 0.85)
        ),
        ProcessFingerprint(
            any: [.argumentContains("@angular/cli"), .argumentBasename("ng")],
            match(kind: .devServer, title: "Angular CLI", summary: "service.angular", confidence: 0.85)
        ),
        ProcessFingerprint(
            any: [.argumentContains("vue-cli-service")],
            match(kind: .devServer, title: "Vue CLI", summary: "service.vuecli", confidence: 0.85)
        ),
        ProcessFingerprint(
            any: [.argumentContains("remix"), .argumentContains("@remix-run")],
            match(kind: .devServer, title: "Remix", summary: "service.remix", confidence: 0.8)
        ),
        ProcessFingerprint(
            any: [.argumentContains("astro")],
            match(kind: .devServer, title: "Astro", summary: "service.astro", confidence: 0.75)
        ),
        ProcessFingerprint(
            any: [.argumentContains("svelte-kit"), .argumentContains("sveltekit")],
            match(kind: .devServer, title: "SvelteKit", summary: "service.sveltekit", confidence: 0.8)
        ),
        ProcessFingerprint(
            any: [.argumentContains("storybook")],
            match(kind: .devServer, title: "Storybook", summary: "service.storybook", confidence: 0.8)
        ),
        // The `serve` static file server: the binary is named `serve` and runs
        // from a directory, nothing more. Matching on "serve" anywhere would
        // also catch `manage.py runserver`, `serve_forever`, and so on.
        ProcessFingerprint(
            all: [.argumentBasename("serve"), .argumentContains("serve")],
            match(kind: .web, title: "serve", summary: "service.staticServer", confidence: 0.6)
        ),

        // --- Python ---
        ProcessFingerprint(
            any: [.argumentContains("manage.py")],
            match(kind: .web, title: "Django", summary: "service.django", confidence: 0.95)
        ),
        ProcessFingerprint(
            any: [.argumentContains("uvicorn"), .argumentContains("gunicorn")],
            match(kind: .api, title: "ASGI / WSGI server", summary: "service.pythonServer", confidence: 0.85)
        ),
        ProcessFingerprint(
            any: [.argumentContains("flask")],
            match(kind: .web, title: "Flask", summary: "service.flask", confidence: 0.85)
        ),
        ProcessFingerprint(
            any: [.argumentContains("http.server"), .argumentContains("SimpleHTTPRequestHandler")],
            match(kind: .web, title: "Python http.server", summary: "service.pythonHTTPServer", confidence: 0.95)
        ),
        ProcessFingerprint(
            any: [.argumentContains("jupyter"), .argumentContains("notebook")],
            match(kind: .web, title: "Jupyter", summary: "service.jupyter", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.argumentContains("streamlit")],
            match(kind: .web, title: "Streamlit", summary: "service.streamlit", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.argumentContains("gradio")],
            match(kind: .web, title: "Gradio", summary: "service.gradio", confidence: 0.85)
        ),

        // --- Databases and caches ---
        ProcessFingerprint(
            any: [.executable("redis-server"), .argumentContains("redis-server")],
            match(kind: .cache, title: "Redis", summary: "service.redis", confidence: 0.95)
        ),
        ProcessFingerprint(
            any: [.executable("valkey-server")],
            match(kind: .cache, title: "Valkey", summary: "service.valkey", confidence: 0.95)
        ),
        ProcessFingerprint(
            any: [.executable("memcached")],
            match(kind: .cache, title: "Memcached", summary: "service.memcached", confidence: 0.95)
        ),
        ProcessFingerprint(
            any: [.executable("postgres"), .executable("postmaster")],
            match(kind: .database, title: "PostgreSQL", summary: "service.postgres", confidence: 0.95)
        ),
        ProcessFingerprint(
            any: [.executable("mysqld")],
            match(kind: .database, title: "MySQL", summary: "service.mysql", confidence: 0.95)
        ),
        ProcessFingerprint(
            any: [.executable("mongod")],
            match(kind: .database, title: "MongoDB", summary: "service.mongodb", confidence: 0.95)
        ),
        ProcessFingerprint(
            any: [.executable("clickhouse")],
            match(kind: .database, title: "ClickHouse", summary: "service.clickhouse", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("influxd")],
            match(kind: .database, title: "InfluxDB", summary: "service.influxdb", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("elasticsearch")],
            match(kind: .database, title: "Elasticsearch", summary: "service.elasticsearch", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("qdrant")],
            match(kind: .database, title: "Qdrant", summary: "service.qdrant", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("ollama")],
            match(kind: .ai, title: "Ollama", summary: "service.ollama", confidence: 0.95)
        ),

        // --- Messaging and infrastructure ---
        ProcessFingerprint(
            any: [.executable("rabbitmq-server"), .argumentContains("rabbitmq")],
            match(kind: .messaging, title: "RabbitMQ", summary: "service.rabbitmq", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("nats-server")],
            match(kind: .messaging, title: "NATS", summary: "service.nats", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("mosquitto")],
            match(kind: .messaging, title: "Mosquitto", summary: "service.mosquitto", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("minio")],
            match(kind: .web, title: "MinIO", summary: "service.minio", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("consul")],
            match(kind: .system, title: "Consul", summary: "service.consul", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("vault")],
            match(kind: .system, title: "Vault", summary: "service.vault", confidence: 0.85)
        ),

        // --- Runtimes we can only name generically ---
        ProcessFingerprint(
            any: [.executable("node")],
            match(kind: .web, title: "Node.js", summary: "service.node", confidence: 0.55)
        ),
        ProcessFingerprint(
            any: [.executable("bun")],
            match(kind: .web, title: "Bun", summary: "service.bun", confidence: 0.55)
        ),
        ProcessFingerprint(
            any: [.executable("deno")],
            match(kind: .web, title: "Deno", summary: "service.deno", confidence: 0.55)
        ),
        ProcessFingerprint(
            any: [.executable("python3"), .executable("python")],
            match(kind: .web, title: "Python", summary: "service.python", confidence: 0.5)
        ),
        ProcessFingerprint(
            any: [.executable("ruby")],
            match(kind: .web, title: "Ruby", summary: "service.ruby", confidence: 0.5)
        ),
        ProcessFingerprint(
            any: [.executable("java")],
            match(kind: .web, title: "Java", summary: "service.java", confidence: 0.5)
        ),
        ProcessFingerprint(
            any: [.executable("go")],
            match(kind: .web, title: "Go", summary: "service.go", confidence: 0.5)
        ),
        ProcessFingerprint(
            any: [.executable("php")],
            match(kind: .web, title: "PHP", summary: "service.php", confidence: 0.5)
        ),
        ProcessFingerprint(
            any: [.executable("nginx")],
            match(kind: .web, title: "nginx", summary: "service.nginx", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("caddy")],
            match(kind: .web, title: "Caddy", summary: "service.caddy", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("httpd"), .executable("apache2")],
            match(kind: .web, title: "Apache", summary: "service.apache", confidence: 0.9)
        ),

        // --- Containers ---
        ProcessFingerprint(
            any: [.pathContains("com.docker"), .pathContains("Docker.app")],
            match(kind: .container, title: "Docker", summary: "service.docker", confidence: 0.85)
        ),
        ProcessFingerprint(
            any: [.pathContains("colima")],
            match(kind: .container, title: "Colima", summary: "service.colima", confidence: 0.8)
        ),
        ProcessFingerprint(
            any: [.pathContains("orbstack"), .pathContains("OrbStack")],
            match(kind: .container, title: "OrbStack", summary: "service.orbstack", confidence: 0.8)
        ),

        // --- Desktop apps that listen locally ---
        ProcessFingerprint(
            any: [.executable("Discord")],
            match(kind: .messaging, title: "Discord", summary: "service.discord", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("WeChat")],
            match(kind: .messaging, title: "WeChat", summary: "service.wechat", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("Slack")],
            match(kind: .messaging, title: "Slack", summary: "service.slack", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("Code Helper"), .pathContains("Visual Studio Code")],
            match(kind: .system, title: "Visual Studio Code", summary: "service.vscode", confidence: 0.85)
        ),

        // --- macOS system services ---
        ProcessFingerprint(
            any: [.executable("ControlCenter")],
            match(kind: .system, title: "AirPlay Receiver", summary: "service.airplay", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("rapportd")],
            match(kind: .system, title: "Continuity / Handoff", summary: "service.rapportd", confidence: 0.9)
        ),
        ProcessFingerprint(
            any: [.executable("sharingd")],
            match(kind: .system, title: "macOS Sharing", summary: "service.sharingd", confidence: 0.85)
        ),
        ProcessFingerprint(
            any: [.executable("mDNSResponder")],
            match(kind: .system, title: "Bonjour", summary: "service.bonjour", confidence: 0.85)
        ),
    ]

    // MARK: - HTTP header fingerprints

    public static let httpFingerprints: [HTTPFingerprint] = [
        HTTPFingerprint(header: "server", contains: "AirTunes",
                        match: match(kind: .system, title: "AirPlay Receiver",
                                     summary: "service.airplay", confidence: 0.95)),
        HTTPFingerprint(header: "x-powered-by", contains: "Express",
                        match: match(kind: .api, title: "Express", summary: "service.express",
                                     confidence: 0.85)),
        HTTPFingerprint(header: "x-powered-by", contains: "Next.js",
                        match: match(kind: .devServer, title: "Next.js", summary: "service.next",
                                     confidence: 0.9)),
        HTTPFingerprint(header: "x-powered-by", contains: "PHP",
                        match: match(kind: .web, title: "PHP", summary: "service.php",
                                     confidence: 0.75)),
        HTTPFingerprint(header: "server", contains: "nginx",
                        match: match(kind: .web, title: "nginx", summary: "service.nginx",
                                     confidence: 0.9)),
        HTTPFingerprint(header: "server", contains: "Caddy",
                        match: match(kind: .web, title: "Caddy", summary: "service.caddy",
                                     confidence: 0.9)),
        HTTPFingerprint(header: "server", contains: "uvicorn",
                        match: match(kind: .api, title: "Uvicorn", summary: "service.uvicorn",
                                     confidence: 0.9)),
        HTTPFingerprint(header: "server", contains: "Werkzeug",
                        match: match(kind: .web, title: "Flask (dev server)",
                                     summary: "service.flask", confidence: 0.85)),
        HTTPFingerprint(header: "server", contains: "gunicorn",
                        match: match(kind: .api, title: "Gunicorn", summary: "service.gunicorn",
                                     confidence: 0.9)),
        HTTPFingerprint(header: "server", contains: "SimpleHTTP",
                        match: match(kind: .web, title: "Python http.server",
                                     summary: "service.pythonHTTPServer", confidence: 0.95)),
        HTTPFingerprint(header: "server", contains: "envoy",
                        match: match(kind: .web, title: "Envoy", summary: "service.envoy",
                                     confidence: 0.85)),
        HTTPFingerprint(header: "x-envoy-upstream-service-time", contains: nil,
                        match: match(kind: .web, title: "Envoy", summary: "service.envoy",
                                     confidence: 0.6)),
        HTTPFingerprint(header: "server", contains: "Jetty",
                        match: match(kind: .web, title: "Jetty", summary: "service.java",
                                     confidence: 0.7)),
        HTTPFingerprint(header: "server", contains: "Apache",
                        match: match(kind: .web, title: "Apache", summary: "service.apache",
                                     confidence: 0.9)),
        HTTPFingerprint(header: "x-amz-request-id", contains: nil,
                        match: match(kind: .web, title: "S3-compatible storage",
                                     summary: "service.s3", confidence: 0.6)),
    ]

    // MARK: - Well-known ports

    public static let portFingerprints: [PortFingerprint] = [
        PortFingerprint(port: 22, match: match(kind: .system, title: "SSH",
                                               summary: "service.ssh", confidence: 0.5)),
        PortFingerprint(port: 80, match: match(kind: .web, title: "HTTP",
                                               summary: "service.http", confidence: 0.4)),
        PortFingerprint(port: 443, match: match(kind: .web, title: "HTTPS",
                                                summary: "service.https", confidence: 0.4)),
        PortFingerprint(port: 3000, match: match(kind: .devServer, title: "Node.js dev server",
                                                 summary: "service.port3000", confidence: 0.3)),
        PortFingerprint(port: 3306, match: match(kind: .database, title: "MySQL",
                                                 summary: "service.mysql", confidence: 0.5)),
        PortFingerprint(port: 5000, match: match(kind: .web, title: "AirPlay Receiver",
                                                 summary: "service.airplay", confidence: 0.4)),
        PortFingerprint(port: 5173, match: match(kind: .devServer, title: "Vite",
                                                 summary: "service.vite", confidence: 0.4)),
        PortFingerprint(port: 5432, match: match(kind: .database, title: "PostgreSQL",
                                                 summary: "service.postgres", confidence: 0.5)),
        PortFingerprint(port: 6379, match: match(kind: .cache, title: "Redis",
                                                 summary: "service.redis", confidence: 0.5)),
        PortFingerprint(port: 7000, match: match(kind: .system, title: "AirPlay Receiver",
                                                 summary: "service.airplay", confidence: 0.4)),
        PortFingerprint(port: 8000, match: match(kind: .devServer, title: "Python dev server",
                                                 summary: "service.port8000", confidence: 0.3)),
        PortFingerprint(port: 8080, match: match(kind: .web, title: "HTTP alt",
                                                 summary: "service.port8080", confidence: 0.3)),
        PortFingerprint(port: 8888, match: match(kind: .web, title: "Jupyter",
                                                 summary: "service.jupyter", confidence: 0.4)),
        PortFingerprint(port: 9092, match: match(kind: .messaging, title: "Kafka",
                                                 summary: "service.kafka", confidence: 0.4)),
        PortFingerprint(port: 11434, match: match(kind: .ai, title: "Ollama",
                                                  summary: "service.ollama", confidence: 0.6)),
        PortFingerprint(port: 27017, match: match(kind: .database, title: "MongoDB",
                                                  summary: "service.mongodb", confidence: 0.5)),
    ]

    private static func match(
        kind: ServiceInfo.Kind, title: String, summary: String, confidence: Double
    ) -> ServiceMatch {
        ServiceMatch(kind: kind, title: title, summaryKey: summary, confidence: confidence)
    }
}
