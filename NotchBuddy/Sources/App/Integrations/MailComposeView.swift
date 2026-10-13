import SwiftUI

// MARK: - Mail

struct MailView: View {
    @ObservedObject var state: AppState
    @State private var to: String = ""
    @State private var subject: String = ""
    @State private var bodyText: String = ""
    @State private var statusMsg: String = ""
    @State private var isSending = false

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("New email").font(.system(size: 12, weight: .semibold))
                    if let name = state.droppedFile?.name {
                        Text(String(format: String(localized: "mail.with %@"), name))
                            .font(.system(size: 12)).foregroundColor(Color(hex: "#8E939C"))
                            .lineLimit(1).truncationMode(.middle)
                    }
                }

                MailField(label: "To", placeholder: "address@example.com", text: $to)
                MailField(label: "Subject", placeholder: state.droppedFile?.name ?? "Subject", text: $subject)

                // Body — TextEditor scrolls internally when text overflows
                TextEditor(text: $bodyText)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .frame(height: 44)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if !statusMsg.isEmpty {
                    Text(statusMsg).font(.system(size: 11)).foregroundColor(Color(hex: "#FF8D97"))
                }

                HStack(spacing: 8) {
                    PrimaryButton(verbatim: isSending ? String(localized: "Sending…") : String(localized: "Send")) {
                        guard !isSending else { return }
                        sendMail()
                    }
                    SecondaryButton("Cancel") {
                        if state.voiceMailDraft != nil {
                            // Prepared by voice: nothing to go back to, close the card.
                            state.voiceMailDraft = nil
                            state.droppedFile = nil
                            NotificationCenter.default.post(name: .islandCollapse, object: nil)
                        } else {
                            state.view = .choose
                        }
                    }
                }
            }
            .padding(.leading, 92)
            .padding(.trailing, 18)
            .padding(.vertical, 8)
        }
        .onAppear { fillFromVoiceDraft() }
        .onChange(of: state.voiceMailDraft) { _, _ in fillFromVoiceDraft() }
    }

    /// A mail prepared by voice arrives filled in; otherwise the dropped file's name.
    private func fillFromVoiceDraft() {
        if let d = state.voiceMailDraft {
            to = d.to
            subject = d.subject.isEmpty ? (state.droppedFile?.name ?? "") : d.subject
            bodyText = d.body
            statusMsg = ""
        } else if subject.isEmpty {
            subject = state.droppedFile?.name ?? ""
        }
    }

    private func sendMail() {
        guard !to.isEmpty else { statusMsg = String(localized: "Missing recipient."); return }
        let subj = subject.isEmpty ? (state.droppedFile?.name ?? "File") : subject

        // Prefer Resend if API key + sender address are configured — except for a mail
        // prepared by voice, which goes through the user's own Apple Mail account.
        let apiKey  = KeychainStore.shared.get("resend-api-key")
        let fromAddr = KeychainStore.shared.get("resend-from")

        if state.voiceMailDraft != nil {
            sendViaAppleMail(to: to, subject: subj)
        } else if let apiKey, let fromAddr {
            isSending = true
            statusMsg = ""
            let recipient = to
            let msgBody  = bodyText
            let fileURL  = state.droppedFile?.url
            Task {
                let ok = await sendViaResend(apiKey: apiKey, from: fromAddr,
                                              to: recipient, subject: subj,
                                              body: msgBody, fileURL: fileURL)
                await MainActor.run {
                    isSending = false
                    if ok { onSuccess(recipient: recipient) }
                    else  { statusMsg = "Resend error — check API key & sender." }
                }
            }
        } else if apiKey != nil && fromAddr == nil {
            // API key set but no sender — guide user instead of silent fallback
            statusMsg = "Set sender address in Settings."
        } else {
            // No Resend — fallback to Mail
            sendViaAppleMail(to: to, subject: subj)
        }
    }

    private func sendViaResend(apiKey: String, from: String, to: String,
                                subject: String, body: String, fileURL: URL?) async -> Bool {
        guard let url = URL(string: "https://api.resend.com/emails") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "from": from,
            "to": [to],
            "subject": subject,
            "text": body.isEmpty ? " " : body
        ]
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            payload["attachments"] = [[
                "filename": fileURL.lastPathComponent,
                "content": data.base64EncodedString()
            ]]
        }
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        request.httpBody = httpBody
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200 || code == 201 { return true }
        print("[Resend] HTTP \(code)")
        return false
    }

    private func sendViaAppleMail(to: String, subject: String) {
        #if APPSTORE
        // App Store: no AppleScript — use NSSharingService to compose (user sends manually)
        guard let service = NSSharingService(named: .composeEmail) else {
            statusMsg = String(localized: "Mail not available.")
            return
        }
        var items: [Any] = [bodyText.isEmpty ? " " : bodyText]
        if let url = state.droppedFile?.url,
           FileManager.default.fileExists(atPath: url.path) {
            items.append(url)
        }
        service.recipients = [to]
        service.subject = subject
        service.perform(withItems: items)
        onSuccess(recipient: to)
        #else
        func asEscape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
        }

        let bodyLines = bodyText.isEmpty ? [""] : bodyText.components(separatedBy: "\n")
        let bodyExpr = bodyLines.map { "\"\(asEscape($0))\"" }.joined(separator: " & linefeed & ")
            + " & return & return"

        let attachBlock: String
        if let url = state.droppedFile?.url,
           FileManager.default.fileExists(atPath: url.path) {
            let escapedPath = asEscape(url.path)
            attachBlock = "make new attachment with properties {file name:(POSIX file \"\(escapedPath)\")} at after the last paragraph of content"
        } else {
            attachBlock = ""
        }

        let script = """
        tell application "Mail"
            set m to make new outgoing message with properties {subject:"\(asEscape(subject))", visible:false}
            set content of m to \(bodyExpr)
            tell m
                make new to recipient at end of to recipients with properties {address:"\(asEscape(to))"}
                \(attachBlock)
            end tell
            delay 1
            send m
        end tell
        """
        // Off the main thread: the script waits for Mail (and has a 1 s delay), which used
        // to freeze the whole island until the mail was sent.
        isSending = true
        statusMsg = ""
        let recipient = to
        Task {
            let message: String? = await Task.detached(priority: .userInitiated) {
                var err: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&err)
                return err.map { "Mail error: \($0["NSAppleScriptErrorMessage"] as? String ?? "unknown")" }
            }.value
            await MainActor.run {
                isSending = false
                if let message { statusMsg = message } else { onSuccess(recipient: recipient) }
            }
        }
        #endif
    }

    private func onSuccess(recipient: String) {
        state.voiceMailDraft = nil
        SoundEngine.shared.play("send")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.wink)
        state.noteMessage = "Email sent to \(recipient)."
        state.view = .note
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
        }
    }
}
