import SwiftUI

struct ProfileAvatarImage: View {
  let avatarID: String
  var size: CGFloat = 44

  var body: some View {
    Image(ProfileAvatar.imageName(for: avatarID))
      .resizable()
      .interpolation(.none)
      .scaledToFit()
      .padding(size * 0.06)
      .frame(width: size, height: size)
      .background(AppTheme.lavender, in: RoundedRectangle(cornerRadius: size * 0.28))
      .accessibilityHidden(true)
  }
}

struct ProfileAvatarPicker: View {
  @Binding var selection: String

  private let columns = [GridItem(.adaptive(minimum: 72), spacing: 10)]

  var body: some View {
    LazyVGrid(columns: columns, spacing: 10) {
      ForEach(ProfileAvatar.allCases) { avatar in
        Button {
          selection = avatar.rawValue
        } label: {
          VStack(spacing: 5) {
            ProfileAvatarImage(avatarID: avatar.rawValue, size: 54)
              .overlay {
                RoundedRectangle(cornerRadius: 15)
                  .strokeBorder(
                    selection == avatar.rawValue ? AppTheme.primary : .clear,
                    lineWidth: 2
                  )
              }
            Text(avatar.title)
              .font(.caption2.weight(.medium))
              .foregroundStyle(AppTheme.ink)
              .lineLimit(1)
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(avatar.title)
        .accessibilityAddTraits(selection == avatar.rawValue ? .isSelected : [])
        .accessibilityIdentifier("profileAvatar_\(avatar.rawValue)")
      }
    }
  }
}
