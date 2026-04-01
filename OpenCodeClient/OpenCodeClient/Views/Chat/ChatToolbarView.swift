//
//  ChatToolbarView.swift
//  OpenCodeClient
//

import SwiftUI

struct ChatToolbarView: View {
    @Bindable var state: AppState
    @Binding var showSessionList: Bool
    @Binding var showRenameAlert: Bool
    @Binding var renameText: String
    var showSettingsInToolbar: Bool
    var onSettingsTap: (() -> Void)?
    
    @State private var showCreateDisabledAlert = false
    @State private var showConfigSheet = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    private var useCompactLabels: Bool {
#if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .phone
#else
        return false
#endif
    }
    
    var body: some View {
        HStack {
            sessionButtons
            Spacer()
            rightButtons
        }
        .padding(.horizontal, LayoutConstants.Spacing.spacious)
        .padding(.vertical, LayoutConstants.MessageList.verticalPadding)
    }
    
    // MARK: - Session Operation Buttons
    private var sessionButtons: some View {
        HStack(spacing: LayoutConstants.Toolbar.buttonSpacing) {
            Button {
                showSessionList = true
            } label: {
                Image(systemName: "list.bullet.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(DesignColors.Brand.primary)
            }
            .accessibilityIdentifier("chat-toolbar-session-list")
            
            Button {
                renameText = state.currentSession?.title ?? ""
                showRenameAlert = true
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            
            Button {
                Task { await state.createSession() }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(state.canCreateSession ? DesignColors.Brand.primary : .gray)
            }
            .disabled(!state.canCreateSession)
            .accessibilityIdentifier("chat-toolbar-create-session")

            if !state.canCreateSession {
                Button {
                    showCreateDisabledAlert = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .alert(L10n.t(.chatCreateDisabledHint), isPresented: $showCreateDisabledAlert) {
            Button(L10n.t(.commonOk)) {}
        }
    }
    
    // MARK: - Right Side Buttons (Model + Agent + Settings)
    private var rightButtons: some View {
        HStack(spacing: DesignSpacing.md) {
            configButton
            ContextUsageButton(state: state)
            
            if showSettingsInToolbar, let onSettingsTap {
                Button {
                    onSettingsTap()
                } label: {
                    Image(systemName: "gear")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
    }
    
    private var configButton: some View {
        Button {
            showConfigSheet = true
        } label: {
            HStack(spacing: 4) {
                Text(state.selectedModel?.shortName ?? "Model")
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(DesignColors.Brand.primary.gradient)
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
        .sheet(isPresented: $showConfigSheet) {
            NavigationStack {
                List {
                    Section(L10n.t(.configureModel)) {
                        ForEach(Array(state.modelPresets.enumerated()), id: \.element.id) { index, preset in
                            Button {
                                state.setSelectedModelIndex(index)
                            } label: {
                                HStack {
                                    Text(preset.displayName)
                                    Spacer()
                                    if state.selectedModelIndex == index {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(DesignColors.Brand.primary)
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                    
                    Section(L10n.t(.configureAgent)) {
                        if state.isLoadingAgents {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else if state.visibleAgents.isEmpty {
                            Text(L10n.t(.configureNoAgents))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(state.visibleAgents.enumerated()), id: \.element.id) { index, agent in
                                Button {
                                    state.setSelectedAgentIndex(index)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(agent.shortName)
                                            if let desc = agent.description, !desc.isEmpty {
                                                Text(desc)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        if state.selectedAgentIndex == index {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(DesignColors.Brand.primary)
                                        }
                                    }
                                }
                                .foregroundColor(.primary)
                            }
                        }
                    }
                }
                .navigationTitle(L10n.t(.configureTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.t(.appDone)) {
                            showConfigSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
