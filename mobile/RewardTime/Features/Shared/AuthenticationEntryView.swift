import SwiftUI

struct AuthenticationWelcomeView: View {
  let onContinueWithoutLogin: () -> Void

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        VStack(spacing: 12) {
          Image(systemName: "hourglass")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(AppTheme.primary)
            .frame(width: 76, height: 76)
            .background(AppTheme.lavender, in: RoundedRectangle(cornerRadius: 24))

          Text("Focus Link")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(AppTheme.ink)

          Text("作業と休憩を、あなたのペースで。")
            .font(.title3.weight(.semibold))
            .foregroundStyle(AppTheme.ink)

          Text("ログインすると、作業履歴やグループ情報を同期できます。")
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryInk)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)

        AuthenticationSettingsSection {
          NotificationCenter.default.post(name: .mobileAuthenticationChanged, object: nil)
        }

        Button("あとで端末設定をする", action: onContinueWithoutLogin)
          .font(.subheadline.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: 44)
          .accessibilityIdentifier("continueWithoutLogin")
      }
      .padding(20)
      .frame(maxWidth: 560)
      .frame(maxWidth: .infinity)
    }
    .background(AppTheme.background.ignoresSafeArea())
    .foregroundStyle(AppTheme.ink)
  }
}

struct SignInRequiredCard: View {
  let title: String
  let message: String
  let onSignIn: () -> Void

  var body: some View {
    SurfaceCard {
      Label(title, systemImage: "person.crop.circle.badge.exclamationmark")
        .font(.headline)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(AppTheme.secondaryInk)
      Button("ログインして続ける", action: onSignIn)
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.primary)
        .accessibilityIdentifier("signInRequired")
    }
  }
}
