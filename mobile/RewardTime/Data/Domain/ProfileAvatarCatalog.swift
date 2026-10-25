enum ProfileAvatar: String, CaseIterable, Identifiable {
  case dragon
  case puppy
  case cat
  case hedgehog
  case rabbit
  case chick
  case bird
  case penguinBlue = "penguin_blue"
  case penguinPink = "penguin_pink"
  case slime

  static let defaultAvatar = ProfileAvatar.chick

  var id: String { rawValue }

  var title: String {
    switch self {
    case .dragon: "ドラゴン"
    case .puppy: "こいぬ"
    case .cat: "ねこ"
    case .hedgehog: "ハリネズミ"
    case .rabbit: "うさぎ"
    case .chick: "ひよこ"
    case .bird: "ことり"
    case .penguinBlue: "あおペンギン"
    case .penguinPink: "ピンクペンギン"
    case .slime: "スライム"
    }
  }

  static func imageName(for id: String?) -> String {
    guard let id, let avatar = ProfileAvatar(rawValue: id) else {
      return defaultAvatar.rawValue
    }
    return avatar.rawValue
  }
}
