@_exported import SwiftProtobuf

// Re-exports SwiftProtobuf so every `import WellSpentAPI` call site keeps
// getting `Wellspent_V1_*`'s `.with { }` builder and types like
// `Google_Protobuf_Timestamp` for free — unchanged from before the Connect
// client (which used to carry this re-export in APIClient.swift) was removed.
