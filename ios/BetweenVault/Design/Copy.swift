import Foundation
import LocalAuthentication

/// Handoff A3 and Part D item 2: one strings file, English only, centralized for future
/// localization. Every user facing literal lives here, including VoiceOver labels and the
/// copy the design boards publish verbatim. Views never hardcode copy.
enum Copy {
    // MARK: Tabs

    static let tabVault = "Vault"
    static let tabExchange = "Exchange"
    static let tabPartner = "Partner"
    static let tabSettings = "Settings"

    // MARK: States

    static let statePrivate = "Private"
    static let stateSealed = "Sealed"
    static let stateShared = "Shared"
    static let changedSinceSent = "Changed since sent"

    static func stateVoiceOver(_ word: String) -> String {
        "State: \(word)."
    }

    static let sealedVoiceOver = "State: Sealed. Ready to send to your partner."
    static let sharedChangedVoiceOver = "State: Shared. Changed since you sent it."

    // MARK: Dates

    /// The compact ladder on note rows (boards 4 and U1).
    static let justNow = "Just now"
    static func minutesAgo(_ count: Int) -> String { "\(count)m ago" }
    static func hoursAgo(_ count: Int) -> String { "\(count)h ago" }
    static func daysAgo(_ count: Int) -> String { "\(count)d ago" }
    static func weeksAgo(_ count: Int) -> String { "\(count)w ago" }

    // MARK: Vault home

    static let startWithEmergency = "Start with Emergency"
    static let emergencyPrompt = "If something happened to you today, what would your partner need? Doctor, insurance, who to call, where the papers are."
    static let writeTheFirstNote = "Write the first note"
    static let starterCategoriesNote = "Six starter categories are created with the vault. Emergency and Other always exist, so the vault is never without a category."
    /// True for iCloud Backup users too: a device backup may hold the store, but the app itself
    /// never uploads anything (spec 24).
    static let localOnlyFooter = "Stored on this iPhone. This app never uploads it."
    static let filterAll = "All"
    static let newCategory = "New category"
    static let lockNow = "Lock now"
    static let edit = "Edit"
    static let newNote = "New note"
    static let emergencyTileSubtitle = "What your partner needs if something happens"

    // MARK: Category management

    static let categoriesTitle = "Categories"
    static let add = "Add"
    static let done = "Done"
    static let builtIn = "Built in"
    static let renameCategory = "Rename category"
    static let newCategoryPrompt = "New category"
    static let save = "Save"
    static let cancel = "Cancel"
    static let delete = "Delete"
    static let name = "Name"
    static let builtInsCannotBeDeleted = "Emergency and Other can be renamed and moved, not deleted."
    static let categoriesFooter = "Tap a name to rename it. \(builtInsCannotBeDeleted) Category changes stay on this iPhone; your partner sees the category only on notes you send."
    static let deleteCategoryFallback = "Delete category?"

    static func deleteCategoryTitle(_ name: String) -> String {
        "Delete \"\(name)\"?"
    }

    /// `destination` is Other under its current name: it can be renamed, and notes follow the key.
    static func deleteCategoryMessage(_ count: Int, movingTo destination: String) -> String {
        switch count {
        case 0: "It has no notes."
        case 1: "Its 1 note moves to \(destination). No notes are deleted."
        default: "Its \(count) notes move to \(destination). No notes are deleted."
        }
    }

    static func categoryFailure(_ error: any Error) -> String {
        switch error as? CategoryError {
        case .builtInCannotBeDeleted: builtInsCannotBeDeleted
        case .notFound: "This category no longer exists."
        case .otherCategoryMissing: "Other is missing, so its notes would have nowhere to go. Nothing was deleted."
        case nil: changeNotSaved
        }
    }

    // MARK: Failures

    static let notSaved = "Not saved"
    static let ok = "OK"
    static let changeNotSaved = "The change could not be saved. Nothing was changed."
    static let noteNotSaved = "The note could not be saved. Your text is still here."

    // MARK: Notes

    static let nothingHereYet = "Nothing here yet"
    static let addANoteToThisCategory = "Add a note to this category."
    static let newNoteTitle = "New note"
    static let editNoteTitle = "Edit note"
    static let title = "Title"
    static let body = "Body"
    static let category = "Category"
    static let none = "None"
    static let addAttachment = "Add attachment"
    static let unlock = "Unlock"
    static let attachmentsArriveLater = "Attachments arrive in a later update."
    static let state = "State"
    static let sharedSetBySending = "Shared is set automatically after you send it. Nothing is shared by editing."
    static let sealForPartner = "Seal for partner"
    static let sealedNotesWait = "Sealed notes wait in Exchange until you send them."
    static let moreActions = "More actions"
    static let moveToCategory = "Move to category"
    static let deleteNote = "Delete note"

    static func newNoteIn(_ category: String) -> String {
        "New note in \(category)"
    }

    static let deleteNoteMessage = "It is removed from this iPhone. Your partner's copy stays on their phone. Deleting is never sent."
    static let deleteNeverSentMessage = "It is removed from this iPhone. It was never sent, so your partner has no copy."

    static func deleteNoteTitle(_ title: String) -> String {
        "Delete \"\(title)\"?"
    }

    static func edited(_ timestamp: String) -> String {
        "Edited \(timestamp)"
    }

    static func noFilteredNotes(state: String, category: String) -> String {
        "No \(state.lowercased()) notes in \(category)"
    }

    static func filteredNoteCount(_ count: Int) -> String {
        count == 1 ? "1 note" : "\(count) notes"
    }

    static func filteredEmptyMessage(count: Int) -> String {
        "This category has \(filteredNoteCount(count)). Clear the filter on the vault home to see \(count == 1 ? "it" : "them")."
    }

    static func hiddenByFilter(_ count: Int, state: String) -> String {
        count == 1 ? "1 note is hidden by the \(state) filter." : "\(count) notes are hidden by the \(state) filter."
    }

    static let notesCouldNotOpen = "These notes could not be opened"
    static let nothingWasDeleted = "Nothing was deleted. Try again in a moment."

    // MARK: Exchange

    static let readyToSend = "Ready to send"
    static let waitingForMe = "Waiting for me"
    static let recentlyExchanged = "Recently exchanged"
    static let nothingSealedYet = "Nothing sealed yet"
    static let sealANote = "Seal a note to get it ready for your partner."
    static let nothingWaiting = "Nothing waiting"
    static let openPartnerFile = "When your partner sends you a file, open it here."
    static let noExchangesYet = "No exchanges yet"
    static let exchangeHistoryHint = "Sent and received items show up here."
    static let toastExchangeReady = "Exchange ready"
    static let toastItemsImported = "3 items imported"
    static let toastClipboardCleared = "Clipboard cleared"
    static let encryptAndShare = "Encrypt & Share"

    // MARK: Partner

    static let fingerprint = "Fingerprint"
    static let partnerCanRecover = "Your partner can recover your vault. This is by design."
    static let unpairPartner = "Unpair partner"
    static let noPartnerPaired = "No partner paired yet"
    static let pairedPartner = "Paired partner"
    static let pairInPerson = "Pair in person, side by side. Nothing is sent over a network."
    static let pairWithPartner = "Pair with partner"
    static let scanPartnersCode = "Scan partner's code"

    // MARK: Pairing (boards 11, 12, 12a to 12c, 13, 13a)

    static func stepOf(_ index: Int, _ count: Int) -> String { "Step \(index) of \(count)" }
    static let letPartnerScan = "Let your partner scan this"
    static let pairingQR = "Pairing QR code"
    static let onPartnersPhone = "On your partner's iPhone: Partner tab, then Scan."
    /// Not on a board: board 11 is drawn for A's first QR only; the return QRs reuse it.
    static let holdUpToPartner = "Hold this up to your partner's camera."
    static let pairInPersonFootnote = "Pair in person. The code only works for the next 5 minutes and only on this screen."
    static let partnerScannedIt = "Next"
    static let scanPartnersCodeTitle = "Scan your partner's code"
    static let notAPairingCode = "That isn't a pairing code. Scan the code on your partner's screen."
    static let wrongStepCode = "That's a different step's code. Scan the code your partner shows now."
    static let ownCode = "That's this iPhone's own code. Scan your partner's screen."
    static let newerVersionCode = "That code is from a newer version. Update Between Vault on both phones."
    static let doBothShow = "Do both phones show this code?"
    static let compareDigits = "Compare digit by digit, side by side."
    static let ifNumbersDiffer = "If the numbers differ, stop. Someone else may be in the middle."
    static let codesMatch = "Codes match"
    static let theyDontMatch = "They don't match"
    static let paired = "Paired"
    static let cameraOff = "Camera access is off"
    static let cameraOffBody = "Scanning your partner's code needs the camera. Nothing is recorded or saved."
    static let cameraOffStep1 = "Open Settings, then \(productName)"
    static let cameraOffStep2 = "Turn on Camera, then come back"
    static let cameraOffFootnote = "Both phones scan once during pairing, so this one needs the camera too."
    static let cancelPairing = "Cancel pairing"
    static let cameraUnavailable = "The camera isn't available"
    static let cameraUnavailableBody = "It may be turned off by Screen Time or a work profile, or in use by another app."
    static let cameraUnavailableStep1 = "Close other apps using the camera and try again"
    static let cameraUnavailableStep2 = "Check Settings, Screen Time, Content & Privacy Restrictions"
    static let tryAgain = "Try again"
    static let pairingDidntFinish = "Pairing didn't finish"
    static let pairingDidntFinishBody = "The steps weren't completed within 5 minutes, or the app was closed partway through."
    static let nothingSavedHere = "Nothing was saved on this iPhone."
    static let timedOutStep1 = "Cancel pairing on your partner's phone too"
    static let timedOutStep2 = "Start again together, side by side"
    static let timedOutFootnote = "Pairing works offline. The two phones never talk over a network, so each one times out on its own."
    static let startAgain = "Start again"
    static let codesDidntMatch = "Pairing stopped. The codes didn't match."
    static let codesDidntMatchBody = "That means this iPhone may have scanned a different phone than your partner's. Nothing was saved."
    static let mismatchStep1 = "Make sure you scan your partner's screen, not a photo or another phone"
    static let mismatchStep2 = "Pair somewhere with no other screens nearby"
    static let pairingNotSaved = "The pairing could not be saved. Nothing was saved on this iPhone. Start again together."
    static let alreadyPaired = "This iPhone is already paired. Unpair first to pair again."

    // MARK: Lock

    /// The wordmark. The handoff keeps it trivially changeable, so it lives in one place.
    static let productName = "Between Vault"
    static let locked = "Locked"
    static let unlockWithFaceID = "Unlock with Face ID"
    static let unlockWithTouchID = "Unlock with Touch ID"
    static let faceID = "Face ID"
    static let touchID = "Touch ID"
    static let openSettings = "Open Settings"

    /// Why biometrics cannot open the vault right now, and what fixes it. The vault passcode
    /// always works, so each reason ends there.
    static func biometryBlocked(_ code: LAError.Code, name: String) -> String? {
        switch code {
        case .biometryNotAvailable: "\(name) is turned off for \(productName). Turn it on in Settings, or use your vault passcode."
        case .biometryNotEnrolled, .passcodeNotSet: "\(name) is not set up on this iPhone. Use your vault passcode."
        case .biometryLockout: "\(name) is locked after too many tries. Use your vault passcode."
        default: nil
        }
    }
    static func biometryChanged(name: String) -> String {
        "\(name) changed on this iPhone. Enter your vault passcode once to use \(name) again."
    }
    static let useVaultPasscode = "Use vault passcode"
    static let useFaceID = "Use Face ID"
    static let useTouchID = "Use Touch ID"
    static let enterVaultPasscode = "Enter vault passcode"
    static func wrongPasscode(triesLeft: Int) -> String {
        triesLeft == 1
            ? "Wrong passcode. 1 try left before a wait."
            : "Wrong passcode. \(triesLeft) tries left before a wait."
    }
    static let passcodeUnreadable = "The passcode could not be checked. Nothing was counted. Try again."
    /// Board 1b. Rounded up, so it never promises less wait than there is.
    static func tryAgainIn(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return minutes == 1 ? "Try again in 1 minute" : "Try again in \(minutes) minutes"
    }
    static let waitBody = "Each wrong try after this makes the wait longer. Your iPhone passcode can't unlock the vault."
    // Board 1b's "Forgot it?" card and the reset (row 2.4). The boards draw no confirmation, so
    // the alert and the typed step below are ours; the RESET rule is row 2.4's.
    static let forgotPasscode = "Forgot passcode?"
    static let forgotIt = "Forgot it?"
    static let resetExplained = "Reset erases the vault on this iPhone. Then your partner sends your recovery file and you restore it, like on a new phone."
    static let notPairedWarning = "Not paired and no backup? Reset means the data is gone."
    static let resetAndRestore = "Reset and restore from partner"
    static let resetVault = "Reset vault"
    static let resetAsksTwice = "Reset asks twice and needs you to type RESET."
    static let resetAlertTitle = "Reset the vault?"
    static let resetAlertPaired = "Your vault passcode, Face ID setting and pairing are erased. Your notes stay on this iPhone, locked, until your partner sends your recovery file."
    static let resetAlertNotPaired = "You are not paired and there is no backup, so every note on this iPhone is erased for good. Nothing can bring them back."
    static let continueReset = "Continue"
    static let typeReset = "Type RESET to erase the vault"
    static let resetWord = "RESET"
    static let eraseVault = "Erase vault"
    static let resetFailed = "The reset did not finish. Try again; it picks up where it stopped."
    static let awaitingRestore = "These notes wait for your recovery file"
    static let awaitingRestoreMessage = "Your partner holds it. Restore from your partner arrives in a later update."
    static func digitsEntered(_ count: Int) -> String { "\(count) of 6 digits entered" }
    static let vaultUnavailable = "Vault unavailable"
    /// States only what is known: after a failed open the app cannot tell whether the data is intact.
    static let storeCouldNotOpen = "The local store could not be opened, so the app cannot start. Do not delete the app."
    static let unlockReason = "Unlock your vault."

    // MARK: Onboarding

    /// Board 2a. The first two clauses of the web promise line; PromiseLineTests pins them.
    static let promiseHero = "Private by default. Shared by choice."
    static let promiseBody = "Everything you write stays on this iPhone. Nothing leaves it unless you decide to send it."
    static let noCloudHero = "No cloud. No account."
    static let noCloudBody = "There is no server and no sign up. Items reach your partner only as an encrypted file you hand over yourself, by AirDrop, Messages or Files."
    static let backupHero = "Your data is yours. Your partner is your backup."
    static let backupLimit = "If both phones are lost and there is no backup, the data is gone. We cannot restore it, because we never had it."
    static let continueLabel = "Continue"
    static let iUnderstand = "I understand"
    static func page(_ index: Int, of count: Int) -> String { "Page \(index) of \(count)" }
    static let back = "Back"
    static let choosePasscode = "Choose a vault passcode"
    static let choosePasscodeBody = "6 digits, different from your iPhone passcode. It unlocks the vault when Face ID doesn't."
    static let choosePasscodeFootnote = "Forget it and you reset the vault, then restore it from your partner."
    /// Not on board 2e: a second entry, so a typo cannot lock the owner out.
    static let confirmPasscode = "Enter it again"
    static let confirmPasscodeBody = "So a typo can't lock you out."
    static let passcodesDidNotMatch = "The two entries didn't match. Choose a passcode again."
    static let createVaultHero = "Create your vault"
    static let createVaultBody = "Your vault is encrypted with a key that never leaves this iPhone."
    static let vaultPasscode = "Vault passcode"
    static let set = "Set"
    static let createVaultFootnote = "Face ID is a shortcut. Your vault passcode always works. Your iPhone passcode never unlocks the vault."
    static let createVault = "Create vault"
    static let vaultNotCreated = "The vault passcode could not be saved. Nothing was created. Try again."

    // MARK: Settings

    static let security = "Security"
        static let autoLock = "Auto-lock"
    /// Settings writes "1 minute" (board 17), onboarding "After 1 minute" (board 2d).
    static func minutes(_ count: Int) -> String { count == 1 ? "1 minute" : "\(count) minutes" }
    static func afterMinutes(_ count: Int) -> String { "After \(minutes(count))" }
    static let clearClipboard = "Clear clipboard"
    static let after60s = "After 60 s"
    static let data = "Data"
    static let exportBackup = "Export backup"
    static let attachmentsUnlock = "Attachments unlock"
    static let comingIn11 = "1.1"
    static let about = "About"
    static let version = "Version"
    static let collectsNothing = "This app collects nothing and has no server to send it to."
}
