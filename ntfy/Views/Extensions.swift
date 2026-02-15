import SwiftUI

struct DisableAutocapitalizationModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            content
                .textInputAutocapitalization(.never)
        } else {
            content
                .autocapitalization(.none)
        }
    }
}

extension View {
    func disableAutocapitalization() -> some View {
        modifier(DisableAutocapitalizationModifier())
    }

    func swipeToDelete(action: @escaping () -> Void) -> some View {
        modifier(SwipeToDeleteModifier(action: action))
    }

    func swipeToMarkAsRead(action: @escaping () -> Void) -> some View {
        modifier(SwipeToMarkAsReadModifier(action: action))
    }

    func prominentButtonStyle() -> some View {
        modifier(ProminentButtonModifier())
    }
}

struct ProminentButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 15, *) {
            content
                .buttonStyle(.borderedProminent)
        } else {
            content
                .padding(EdgeInsets(top: 10.0, leading: 10.0, bottom: 10.0, trailing: 10.0))
                .foregroundColor(.white)
                .background(Color.accentColor)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white, lineWidth: 2)
                )
        }
    }
}

struct SwipeToDeleteModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            content
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive, action: action) {
                        Label("Delete", systemImage: "trash.circle")
                    }
                }
        } else {
            content
        }
    }
}

struct SwipeToMarkAsReadModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            content
                .swipeActions(edge: .leading) {
                    Button(action: action) {
                        Label("Read", systemImage: "envelope.open")
                    }
                    .tint(.blue)
                }
        } else {
            content
        }
    }
}
