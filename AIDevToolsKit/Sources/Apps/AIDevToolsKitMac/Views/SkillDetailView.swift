import MarkdownUI
import ProviderRegistryService
import SkillScannerSDK
import SkillService
import SwiftUI

struct SkillDetailView: View {
    let skill: SkillInfo
    let evalConfig: RepositoryEvalConfig?
    let evalRegistry: EvalProviderRegistry?
    var onNavigateToEvals: (() -> Void)?

    @AppStorage("skillDetailTab") private var selectedTab: DetailTab = .skill
    @State private var selectedFileTab: URL?
    @State private var content: SkillContent?
    @State private var loadError: String?

    private enum DetailTab: String, Hashable {
        case skill
        case evals
    }

    private var fileTabs: [(name: String, url: URL)] {
        let mainURL = resolveSkillFileURL(skill.path)
        var result = [("SKILL.md", mainURL)]
        for ref in skill.referenceFiles {
            result.append((ref.name, ref.url))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            if evalConfig != nil {
                Picker(selection: $selectedTab) {
                    Text("Skill").tag(DetailTab.skill)
                    Text("Evals").tag(DetailTab.evals)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding([.horizontal, .top])
            }

            switch selectedTab {
            case .skill:
                skillContent
            case .evals:
                if let evalConfig {
                    VStack(spacing: 0) {
                        if onNavigateToEvals != nil {
                            HStack {
                                Spacer()
                                Button {
                                    onNavigateToEvals?()
                                } label: {
                                    Label("View All Evals", systemImage: "arrow.up.right")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding([.horizontal, .top])
                        }
                        EvalResultsView(config: evalConfig, skillName: skill.name, registry: evalRegistry!)
                            .id(skill.name)
                    }
                }
            }
        }
        .navigationTitle(skill.name)
        .task(id: skill.path) {
            selectedTab = .skill
            selectedFileTab = resolveSkillFileURL(skill.path)
        }
        .onChange(of: selectedFileTab) { _, newValue in
            guard let url = newValue else { return }
            loadContent(from: url)
        }
    }

    private var skillContent: some View {
        VStack(spacing: 0) {
            Picker(selection: $selectedFileTab) {
                ForEach(fileTabs, id: \.url) { tab in
                    Text(tab.name).tag(Optional(tab.url))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Group {
                if let content {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            frontMatterSection(content.frontMatter)
                            if !content.frontMatter.isEmpty {
                                Divider()
                            }
                            Markdown(content.body)
                                .markdownTheme(.gitHub.text {
                                    ForegroundColor(.primary)
                                    FontSize(14)
                                })
                                .textSelection(.enabled)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if let loadError {
                    ContentUnavailableView("Failed to Load Skill", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else {
                    ProgressView()
                }
            }
        }
    }

    private func loadContent(from url: URL) {
        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            content = SkillContent(parsing: raw)
            loadError = nil
        } catch {
            content = nil
            loadError = error.localizedDescription
        }
    }

    private func resolveSkillFileURL(_ url: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url.appendingPathComponent("SKILL.md")
        }
        return url
    }

    @ViewBuilder
    private func frontMatterSection(_ pairs: [(key: String, value: String)]) -> some View {
        if !pairs.isEmpty {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    GridRow {
                        Text("\(pair.key):")
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.leading)
                        Text(pair.value)
                            .textSelection(.enabled)
                            .gridColumnAlignment(.leading)
                    }
                }
            }
            .font(.body)
        }
    }
}
