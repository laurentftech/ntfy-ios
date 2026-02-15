import SwiftUI

struct NotificationRowView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var notification: Notification
    @Binding var showCopiedToast: Bool
    var showTopicBadge: Bool = false

    var body: some View {
        notificationRow
            .swipeToDelete {
                store.delete(notification: notification)
            }
    }

    private var notificationRow: some View {
        HStack(alignment: .top, spacing: 8) {
            // Blue indicator for unread messages
            if !notification.seen {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
            
            VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 2) {
                Text(notification.shortDateTime())
                    .font(.subheadline)
                    .foregroundColor(.gray)
                if [1,2,4,5].contains(notification.priority) {
                    Image("priority-\(notification.priority)")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                }
                if showTopicBadge, let subscription = notification.subscription {
                    Spacer()
                    Text(subscription.topicName())
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.8))
                        .cornerRadius(4)
                }
            }
            .padding([.bottom], 2)
            if let title = notification.formatTitle(), title != "" {
                Text(title)
                    .font(.headline)
                    .bold()
                    .padding([.bottom], 2)
            }
            Text(notification.formatMessage())
                .font(.body)
            if !notification.nonEmojiTags().isEmpty {
                Text("Tags: " + notification.nonEmojiTags().joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding([.top], 2)
            }
            if !notification.actionsList().isEmpty {
                HStack {
                    ForEach(notification.actionsList()) { action in
                        ActionButton(action: action)
                    }
                }
                .padding([.top], 5)
            }
            }
        }
        .padding(.all, 4)
        .contextMenu {
            Button {
                var text = ""
                if let title = notification.formatTitle(), !title.isEmpty {
                    text = title + "\n"
                }
                text += notification.formatMessage()
                UIPasteboard.general.string = text
                withAnimation {
                    showCopiedToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        showCopiedToast = false
                    }
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}

struct ActionButton: View {
    let action: Action

    var body: some View {
        Button(action: {
            ActionExecutor.execute(action)
        }) {
            Text(action.label)
        }
        .prominentButtonStyle()
    }
}
