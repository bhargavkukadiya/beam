import AppKit
import BeamCore
import SwiftUI

@MainActor
struct ResultView: View {
    private let data: ScanResultViewData
    private let contactService: any ContactSaving

    init(data: ScanResultViewData, contactService: any ContactSaving) {
        self.data = data
        self.contactService = contactService
    }

    @State private var copiedText: String? = nil
    @State private var contactSaved = false
    @State private var isSavingContact = false
    @State private var contactError: String? = nil
    @State private var pendingUntrustedURL: URL? = nil
    @State private var showUntrustedURLAlert = false
    @State private var selectedTab: DisplayMode = .formatted
    @State private var appeared = false

    enum DisplayMode: String, CaseIterable {
        case formatted = "Formatted"
        case raw = "Raw"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconBackgroundColor)
                        .frame(width: 44, height: 44)

                    Image(systemName: data.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(iconGradient)
                        .scaleEffect(appeared ? 1.0 : 0.5)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: appeared)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(data.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)

                    if data.isSuccess {
                        Text(subtitleText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Format toggle for JSON / structured data
                if data.isSuccess && (data.jsonInfo != nil || data.wifiInfo != nil || data.contactInfo != nil) {
                    Picker("", selection: $selectedTab) {
                        ForEach(DisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            // Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(displayContent)
                        .font(.system(size: 13, weight: .regular, design: isMonospaced ? .monospaced : .default))
                        .foregroundColor(data.isSuccess ? .primary : .secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .padding(.horizontal, 16)

            // Smart Action Buttons Bar
            HStack(spacing: 8) {
                if data.isSuccess {
                    contextualActionButtons
                } else {
                    // Empty / Error button
                    Button {
                        NSApp.keyWindow?.close()
                    } label: {
                        Text("Dismiss")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            // Global copy shortcut ⌘C
            if data.isSuccess {
                Button {
                    copyToClipboard(data.rawMessage)
                } label: {
                    EmptyView()
                }
                .buttonStyle(.plain)
                .keyboardShortcut("c", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appeared = true
            }
        }
        .alert(
            "Contacts",
            isPresented: Binding(
                get: { contactError != nil },
                set: { if !$0 { contactError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                contactError = nil
            }
        } message: {
            Text(contactError ?? "")
        }
        .alert("Open External Link?", isPresented: $showUntrustedURLAlert) {
            Button("Open", role: .destructive) {
                if let url = pendingUntrustedURL {
                    NSWorkspace.shared.open(url)
                }
                pendingUntrustedURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingUntrustedURL = nil
            }
        } message: {
            if let url = pendingUntrustedURL {
                Text(
                    "This QR code wants to open an application with custom scheme '\(url.scheme ?? "")':\n\n\(url.absoluteString)\n\nOpening unknown URL schemes can trigger actions in external applications. Do you want to continue?"
                )
            } else {
                Text("Do you want to open this link?")
            }
        }
    }

    // MARK: - Display Content

    private var displayContent: String {
        if selectedTab == .raw {
            return data.rawMessage
        }
        return data.message
    }

    private var isMonospaced: Bool {
        guard data.isSuccess else { return false }
        if selectedTab == .raw || data.jsonInfo != nil { return true }
        return false
    }

    private var subtitleText: String {
        if let wifi = data.wifiInfo { return "SSID: \(wifi.ssid)" }
        if let contact = data.contactInfo { return contact.name ?? "Contact Card" }
        if let otp = data.otpInfo { return otp.issuer ?? "Two-Factor Auth" }
        return "Scanned content below"
    }

    // MARK: - Smart Contextual Action Buttons

    @ViewBuilder
    private var contextualActionButtons: some View {
        // 1. WiFi Specific Actions
        if let wifi = data.wifiInfo {
            if let pass = wifi.password, !pass.isEmpty, !wifi.isPasswordRedacted {
                actionButton(
                    title: isCopied(pass) ? "Password Copied!" : "Copy Password",
                    icon: isCopied(pass) ? "checkmark.circle.fill" : "key.fill",
                    isPrimary: true,
                    isSuccess: isCopied(pass)
                ) {
                    copyToClipboard(pass)
                }
                .keyboardShortcut(.defaultAction)
            }

            actionButton(
                title: isCopied(data.rawMessage) ? "Config Copied!" : "Copy All",
                icon: isCopied(data.rawMessage) ? "checkmark.circle.fill" : "doc.on.doc",
                isPrimary: wifi.password == nil || wifi.isPasswordRedacted,
                isSuccess: isCopied(data.rawMessage)
            ) {
                copyToClipboard(data.rawMessage)
            }

            actionButton(
                title: "Network Settings",
                icon: "wifi",
                isPrimary: false,
                isSuccess: false
            ) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        // 2. Contact Specific Actions
        else if let contact = data.contactInfo {
            actionButton(
                title: isSavingContact ? "Saving..." : (contactSaved ? "Added to Contacts!" : "Add to Contacts"),
                icon: contactSaved ? "checkmark.circle.fill" : "person.crop.circle.badge.plus",
                isPrimary: true,
                isSuccess: contactSaved
            ) {
                guard !isSavingContact else { return }
                isSavingContact = true
                Task { @MainActor in
                    do {
                        try await contactService.save(contact)
                        withAnimation(.spring(response: 0.3)) { contactSaved = true }
                        triggerHaptic()
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            withAnimation { contactSaved = false }
                        }
                    } catch {
                        contactError = error.localizedDescription
                    }
                    isSavingContact = false
                }
            }
            .keyboardShortcut(.defaultAction)

            if let phone = contact.phone, let url = URL(string: "tel:\(phone)") {
                actionButton(title: "Call", icon: "phone.fill", isPrimary: false, isSuccess: false) {
                    NSWorkspace.shared.open(url)
                }
            }

            if let email = contact.email, let url = URL(string: "mailto:\(email)") {
                actionButton(title: "Email", icon: "envelope.fill", isPrimary: false, isSuccess: false) {
                    NSWorkspace.shared.open(url)
                }
            }

            actionButton(
                title: isCopied(data.rawMessage) ? "Copied!" : "Copy",
                icon: isCopied(data.rawMessage) ? "checkmark.circle.fill" : "doc.on.doc",
                isPrimary: false,
                isSuccess: isCopied(data.rawMessage)
            ) {
                copyToClipboard(data.rawMessage)
            }
        }
        // 3. OTP Specific Actions
        else if let otp = data.otpInfo {
            if !otp.isRedacted {
                actionButton(
                    title: isCopied(otp.secret) ? "Secret Copied!" : "Copy Secret",
                    icon: isCopied(otp.secret) ? "checkmark.circle.fill" : "key.fill",
                    isPrimary: true,
                    isSuccess: isCopied(otp.secret)
                ) {
                    copyToClipboard(otp.secret)
                }
                .keyboardShortcut(.defaultAction)

                actionButton(title: "Open Authenticator", icon: "lock.shield", isPrimary: false, isSuccess: false) {
                    NSWorkspace.shared.open(otp.url)
                }
            } else {
                actionButton(
                    title: isCopied(data.rawMessage) ? "Copied!" : "Copy",
                    icon: isCopied(data.rawMessage) ? "checkmark.circle.fill" : "doc.on.doc",
                    isPrimary: true,
                    isSuccess: isCopied(data.rawMessage)
                ) {
                    copyToClipboard(data.rawMessage)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        // 4. URL / Actionable Links
        else if let link = actionableLink {
            actionButton(
                title: link.title,
                icon: link.icon,
                isPrimary: true,
                isSuccess: false
            ) {
                if link.isSafe {
                    NSWorkspace.shared.open(link.url)
                } else {
                    pendingUntrustedURL = link.url
                    showUntrustedURLAlert = true
                }
            }
            .keyboardShortcut(.defaultAction)

            actionButton(
                title: isCopied(data.rawMessage) ? "Copied!" : "Copy URL",
                icon: isCopied(data.rawMessage) ? "checkmark.circle.fill" : "doc.on.doc",
                isPrimary: false,
                isSuccess: isCopied(data.rawMessage)
            ) {
                copyToClipboard(data.rawMessage)
            }

            actionButton(title: "Share", icon: "square.and.arrow.up", isPrimary: false, isSuccess: false) {
                shareURL(link.url)
            }
        }
        // 5. Default Text / JSON
        else {
            let textToCopy = selectedTab == .formatted ? data.message : data.rawMessage
            actionButton(
                title: isCopied(textToCopy) ? "Copied!" : "Copy",
                icon: isCopied(textToCopy) ? "checkmark.circle.fill" : "doc.on.doc",
                isPrimary: true,
                isSuccess: isCopied(textToCopy)
            ) {
                copyToClipboard(textToCopy)
            }
            .keyboardShortcut(.defaultAction)

            actionButton(title: "Share", icon: "square.and.arrow.up", isPrimary: false, isSuccess: false) {
                shareText(textToCopy)
            }
        }
    }

    // MARK: - Action Button Component

    private func actionButton(
        title: String, icon: String, isPrimary: Bool, isSuccess: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(buttonBackgroundColor(isPrimary: isPrimary, isSuccess: isSuccess))
            )
            .foregroundColor(buttonForegroundColor(isPrimary: isPrimary, isSuccess: isSuccess))
        }
        .buttonStyle(.plain)
    }

    private func buttonBackgroundColor(isPrimary: Bool, isSuccess: Bool) -> Color {
        if isSuccess {
            return Color.green.opacity(0.18)
        }
        if isPrimary {
            return Color.accentColor.opacity(0.15)
        }
        return Color.secondary.opacity(0.1)
    }

    private func buttonForegroundColor(isPrimary: Bool, isSuccess: Bool) -> Color {
        if isSuccess { return .green }
        if isPrimary { return .accentColor }
        return .primary
    }

    // MARK: - Helpers & Actions

    private func isCopied(_ text: String) -> Bool {
        return copiedText == text
    }

    private func copyToClipboard(_ text: String) {
        ClipboardService.shared.copy(text)
        triggerHaptic()

        withAnimation(.spring(response: 0.3)) {
            copiedText = text
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if self.copiedText == text {
                withAnimation {
                    self.copiedText = nil
                }
            }
        }
    }

    private func triggerHaptic() {
        FeedbackService.confirmAction()
    }

    private func shareURL(_ url: URL) {
        guard let window = NSApp.keyWindow, let view = window.contentView else { return }
        SharingService.shared.present(items: [url], from: view)
    }

    private func shareText(_ text: String) {
        guard let window = NSApp.keyWindow, let view = window.contentView else { return }
        SharingService.shared.present(items: [text], from: view)
    }

    private var actionableLink: ActionableLink? {
        data.actionableLink
    }

    private var iconBackgroundColor: Color {
        switch data.result {
        case .success: return Color.green.opacity(0.12)
        case .noQRCodeFound: return Color.orange.opacity(0.12)
        case .error: return Color.red.opacity(0.12)
        }
    }

    private var iconGradient: some ShapeStyle {
        switch data.result {
        case .success:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.green, .mint],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .noQRCodeFound:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.orange, .yellow],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .error:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.red, .pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}
