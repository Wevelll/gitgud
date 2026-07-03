/// Day-Dial MCP tool layer: consent-gated tool handlers over `core`, plus an
/// in-memory repository. Transport (stdio / Streamable HTTP) layers on top.
library;

export 'src/consent.dart';
export 'src/repository.dart';
export 'src/seed.dart';
export 'src/tools.dart';
export 'src/protocol/mcp_server.dart';
export 'src/transport/stdio_transport.dart';
export 'src/transport/http_transport.dart';
export 'src/transport/data_api_server.dart';
