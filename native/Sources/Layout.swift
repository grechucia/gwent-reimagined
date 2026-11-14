// Named positions of fixed UI elements, in the virtual 1920x1080 space.
import Foundation

/// Elements shared by many screens.
enum ScreenLayout {
    static let backButton = R(40, 24, 190, 50)
    static let wideBackButton = R(40, 24, 220, 50)
    static let deckBackButton = R(40, 24, 200, 50)
    static let quitButton = R(1690, 24, 190, 46)
    static let optionsPanel = R(360, 40, 1200, 1000)
    static let licensesPanel = R(360, 110, 1200, 860)
    static let rulesPanel = R(260, 90, 1400, 940)
    static let savePromptPanel = R(360, 120, 1200, 840)
    static let cardPreviewCard = R(1538, 232, 330, 474)
    static let cardPreviewText = R(1528, 714, 350, 360)
}

/// Deck builder screen.
enum BuilderLayout {
    static let collectionColumn = R(40, 222, 800, 818)
    static let deckColumn = R(1080, 222, 800, 818)
    static let leaderCard = R(895, 196, 130, 187)
    static let changeLeaderButton = R(875, 386, 170, 28)
    static let saveButton = R(865, 800, 190, 52)
    static let startButton = R(865, 862, 190, 52)
}

/// Career ladder screen.
enum CareerLayout {
    static let chaptersColumn = R(40, 150, 380, 640)
    static let deckColumn = R(1520, 150, 360, 640)
}

/// Read-only deck preview.
enum DeckPreviewLayout {
    static let infoPanel = R(60, 150, 400, 830)
    static let cardsArea = R(490, 150, 1370, 830)
}

/// Fixed positions of board elements in the virtual 1920x1080 space (they match the board image).
enum BoardLayout {
    static let rowsLeft: Float = 567
    static let rowsWidth: Float = 946
    static let allRows = R(567, 5, 946, 816)
    static let rowScoreX: Float = 534
    static let humanPanel = R(0, 666, 450, 135)
    static let computerPanel = R(0, 263, 450, 135)
    static let rulesButton = R(1540, 16, 190, 46)
    static let passButton = R(292, 848, 150, 50)
    static let giveUpButton = R(292, 944, 150, 50)
    static let exitButton = R(1680, 1018, 180, 46)
    static let musicButtonsX: Float = 1570
    static let bottomButtonsY: Float = 1018
    static let hand = R(580, 843, 932, 128)
    static let weatherSlot = R(141, 448, 279, 138)
    static let humanLeader = R(142, 835, 96, 132)
    static let computerLeader = R(142, 83, 96, 132)
    static let factionAbilityButton = R(160, 612, 150, 34)
    static let rowChoiceBar = R(560, 820, 960, 46)
    static let endOfMatchBanner = R(660, 90, 600, 360)
}

