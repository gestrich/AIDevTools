struct AuthorOption {
    let login: String
    let name: String

    var displayLabel: String {
        if name.isEmpty || name == login {
            return login
        }
        return "\(name) (\(login))"
    }
}
