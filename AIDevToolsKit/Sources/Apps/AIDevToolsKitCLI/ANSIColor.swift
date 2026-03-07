enum ANSIColor: String {
    case blue = "\u{1B}[0;34m"
    case cyan = "\u{1B}[0;36m"
    case green = "\u{1B}[0;32m"
    case red = "\u{1B}[0;31m"
    case reset = "\u{1B}[0m"
    case yellow = "\u{1B}[1;33m"
}

func printColored(_ text: String, color: ANSIColor) {
    print("\(color.rawValue)\(text)\(ANSIColor.reset.rawValue)")
}
