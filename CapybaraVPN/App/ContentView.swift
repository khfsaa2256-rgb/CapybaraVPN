import SwiftUI

/// 域名拦截过滤主界面：App 内手动添加/管理域名规则
struct ContentView: View {
    @StateObject var store: DomainRuleStore
    @State private var newDomain = ""
    @State private var newAction: FilterAction = .block
    @State private var filterOn = true
    @State private var addError: String?

    init(store: DomainRuleStore) {
        _store = StateObject(wrappedValue: store)
        // 规则库注入过滤引擎（URLFilterProtocol 通过引擎查规则）
        FilterEngine.shared.store = store
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $filterOn) {
                        Label(
                            filterOn ? "拦截已开启" : "拦截已关闭",
                            systemImage: filterOn ? "shield.fill" : "shield.slash"
                        )
                        .foregroundStyle(filterOn ? Color.accentColor : .secondary)
                    }
                    .onChange(of: filterOn) { on in
                        if on {
                            FilterEngine.shared.register()
                        } else {
                            FilterEngine.shared.unregister()
                        }
                    }
                } header: {
                    Text("过滤开关")
                } footer: {
                    Text("开启后，App 内发起的 HTTP/HTTPS 请求将按下方规则过滤。URLProtocol 对 HTTPS 的生效范围有限，完整拦截请配合 VPN 隧道（见 README）。")
                }

                Section {
                    TextField("输入域名，如 ads.example.com", text: $newDomain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("动作", selection: $newAction) {
                        ForEach(FilterAction.allCases) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                    .pickerStyle(.segmented)
                    Button("添加规则") {
                        addRule()
                    }
                    .disabled(newDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let addError {
                        Text(addError).foregroundStyle(.red).font(.footnote)
                    }
                } header: {
                    Text("添加域名规则")
                }

                Section {
                    if store.rules.isEmpty {
                        Text("暂无规则，请在上方添加域名")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.rules) { rule in
                            RuleRow(store: store, ruleID: rule.id)
                        }
                        .onDelete { indexSet in
                            for idx in indexSet {
                                store.remove(id: store.rules[idx].id)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("规则列表")
                        Spacer()
                        if !store.rules.isEmpty {
                            Button("清空") { store.clearAll() }
                        }
                    }
                }

                Section {
                    if store.logs.isEmpty {
                        Text("暂无拦截记录")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.logs) { log in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.url)
                                    .font(.footnote)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(log.action.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(log.action == .block ? .red : .orange)
                                    if let ruleDomain = log.ruleDomain {
                                        Text("命中：\(ruleDomain)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(log.at, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("拦截日志")
                        Spacer()
                        if !store.logs.isEmpty {
                            Button("清空") { store.clearLogs() }
                        }
                    }
                }
            }
            .navigationTitle("域名拦截")
        }
    }

    private func addRule() {
        addError = nil
        if store.add(domain: newDomain, action: newAction) {
            newDomain = ""
        } else {
            addError = "域名无效或该规则已存在"
        }
    }
}

/// 单条规则行：域名 + 动作菜单 + 启停开关
struct RuleRow: View {
    @ObservedObject var store: DomainRuleStore
    let ruleID: UUID

    private var current: DomainRule? {
        store.rules.first { $0.id == ruleID }
    }

    var body: some View {
        if let rule = current {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.domain)
                        .font(.body)
                    if !rule.note.isEmpty {
                        Text(rule.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Picker("动作", selection: Binding(
                    get: { rule.action },
                    set: { store.setAction(id: rule.id, action: $0) }
                )) {
                    ForEach(FilterAction.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 92)
                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { store.setEnabled(id: rule.id, enabled: $0) }
                ))
                .labelsHidden()
            }
        }
    }
}
