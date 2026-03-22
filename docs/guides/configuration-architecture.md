# Configuration Architecture

Two centralized services for configuration and data management:

## ConfigurationService

**Purpose**: Manages credentials and settings via JSON files

**Location**: A stored directory for app data, configured in settings (e.g., `<appDataDir>/*.json`)

**Example Usage**:
```swift
let configService = try ConfigurationService()
let config = try configService.get(MyServiceConfiguration.self, from: "my-service")
```

All configuration files should be placed in the app data directory and use JSON format.

**Example** `my-service.json`:
```json
{
  "userName": "your-username",
  "password": "your-password",
  "baseURL": "https://service.example.com"
}
```

**Example Service Pattern**:
```swift
public class MyService {
    public init(configurationService: ConfigurationService) throws {
        let config = try configurationService.get(MyServiceConfiguration.self, from: "my-service")
        self.client = MyClient(token: config.token)
    }
}
```

---

## DataPathsService

**Purpose**: Manages file system paths where services store data

**Location**: `<appDataDir>/data/`

**Example Usage**:
```swift
let dataPathsService = try DataPathsService()
let path = try dataPathsService.path(for: .myServiceData)  // Type-safe enum
```

**Example Directory Structure**:
```
<appDataDir>/data/
├── my-service/
│   ├── builds/
│   └── artifacts/
└── app/
    └── database/          (SwiftData store)
```

**Example ServicePath Enum** (Type-safe paths):
```swift
public enum ServicePath {
    case myServiceBuilds      // <appDataDir>/data/my-service/builds/
    case myServiceArtifacts   // <appDataDir>/data/my-service/artifacts/
    case appDatabase          // <appDataDir>/data/app/database/
}
```

**Example Service Integration**:
```swift
public class MyService {
    public init(
        configurationService: ConfigurationService,
        dataPathsService: DataPathsService
    ) throws {
        let config = try configurationService.get(MyServiceConfiguration.self, from: "my-service")

        self.buildsPath = try dataPathsService.path(for: .myServiceBuilds)
        self.artifactsPath = try dataPathsService.path(for: .myServiceArtifacts)

        self.client = MyClient(token: config.token)
    }
}
```

---

## Design Principles

1. **Single Source of Truth**: One service per concern (config vs data paths)
2. **Fail Fast**: Missing configuration crashes at startup with clear errors
3. **Type-Safe**: Strongly-typed configuration and enum-based paths
4. **No Arguments**: Both services use hardcoded root paths
5. **Auto-Creation**: DataPathsService creates directories automatically

---

## Example App Initialization

```swift
@main
struct MyApp: App {
    init() {
        let configService = try ConfigurationService()
        let dataPathsService = try DataPathsService()

        let myService = try MyService(
            configurationService: configService,
            dataPathsService: dataPathsService
        )
    }
}
```
