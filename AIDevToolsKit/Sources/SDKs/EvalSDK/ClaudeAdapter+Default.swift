import ClaudeCLISDK

extension ClaudeAdapter {
    public init(debug: Bool = false) {
        self.init(client: ClaudeCLIClient(), debug: debug)
    }
}
