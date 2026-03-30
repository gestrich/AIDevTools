/// Marker protocol for Feature-layer use cases.
/// Conforming types must be `struct`s — never `class` or `actor`.
public protocol UseCase: Sendable {}

/// Marker protocol for streaming Feature-layer use cases.
/// Conforming types must be `struct`s and expose a public method returning
/// `AsyncThrowingStream` or `AsyncStream`.
public protocol StreamingUseCase: Sendable {}
