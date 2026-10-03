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
    // Board U2, and Send again for a Shared note the partner says never arrived.
    static let sealUpdate = "Seal update"
    static let sealUpdateHelper = "Moves it to Sealed. It waits in Exchange until you send it."
    static let changedSinceSentNotice = "You changed it after you sent it. Your partner only gets this version when you send it."
    static let sendAgain = "Send again"
    static let sendAgainHelper = "Seals it once more, if your partner didn't get it. Sending a version twice changes nothing on their phone."
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
    // Boards 7, U3, 8, 18.
    static func readyToSendCount(_ count: Int) -> String { count == 0 ? readyToSend : "\(readyToSend) · \(count)" }
    static let newTag = "New"
    static let updateTag = "Update"
    static let outboxFooter = "These are sealed. They stay on this iPhone until you review them and send one encrypted file."
    /// Sent, not delivered: never claims the partner holds a copy.
    static let updateFooter = "Update replaces the version you sent before, unless your partner changed it too. Then they choose which to keep."
    static let reviewAndSend = "Review and send"
    static let pairFirstToSend = "Pair with your partner first. A package only opens on their paired iPhone."
    static let exactlyWhatLeaves = "Exactly what leaves this iPhone"
    static func itemsEncrypted(_ count: Int) -> String {
        "\(count == 1 ? "1 item" : "\(count) items"), encrypted so only your partner's paired iPhone can open them."
    }
    static func includedLine(_ count: Int) -> String {
        "titles, text and categories of \(count == 1 ? "this note" : "these \(count) notes")."
    }
    static let included = "Included:"
    static let notIncluded = "Not included:"
    static let notIncludedLine = "anything else in your vault."
    static let handOverNext = "You choose how to hand it over next: AirDrop, Messages or Files."
    /// Shared means sent, not delivered: the copy never claims the partner has it.
    // Boards P1 to P5: the Partner tab, same components as Exchange (replaces 14).
    static let pairedWithPartner = "Paired with your partner"
    static func pairedSince(_ date: Date, fingerprint: String) -> String {
        "Since \(date.formatted(.dateTime.month(.abbreviated).year())) · fingerprint …\(fingerprint.suffix(4))"
    }
    static let verified = "Verified"
    static let recoveryUpToDate = "Recovery up to date"
    static let recoveryNotSent = "Recovery not sent"
    static let recoveryNotConfirmed = "Recovery not confirmed"
    static let recoveryNeedsUpdate = "Recovery needs updating"
    static let allSetBody = "You can each recover the other's vault. Nothing needs doing."
    static let waitingForTheirCopy = "Your partner holds your recovery copy. Theirs arrives when they send it from their Partner tab."
    static let updateRecoveryCopy = "Update recovery copy"
    static let sendRecoveryCopy = "Send recovery copy"
    static let nearbyRecoveryCaption = "Side by side, over the nearby connection. About 10 seconds."
    static let recoveryFileFallbackSub = "AirDrop, Messages or Files. Confirmed when you next meet."
    static let recoverySection = "Recovery"
    static let yourCopyOnTheirPhone = "Your copy on their phone"
    static let theirCopyOnYourPhone = "Their copy on your phone"
    static func updatedUpToDate(_ date: Date) -> String { "Updated \(date.formatted(.dateTime.month(.abbreviated).day())) · up to date" }
    static let notSentYet = "Not sent yet"
    static func sentAsFileNotConfirmedOn(_ date: Date) -> String { "Sent as a file \(date.formatted(.dateTime.month(.abbreviated).day())) · not confirmed" }
    static let needsUpdatingPairedAgain = "Needs updating · you paired again since"
    static let notReceivedYet = "Not received yet"
    static let recoveryFootnoteAllSet = "Each phone holds the other's encrypted recovery copy. It is how a lost phone gets its vault back."
    /// Honest about the key only copy (owner's choice): it brings back the key, not a snapshot.
    static let recoveryFootnotePending = "Until your partner's phone holds your recovery copy, a lost phone could not get its vault back."
    static let trustSection = "Trust"
    static let compareFingerprints = "Compare fingerprints"
    static let howRecoveryWorks = "How recovery works"
    static let unpairRow = "Unpair"
    static let compareFingerprintsBody = "Open this screen on both phones, side by side. They must show exactly the same."
    static let compareFingerprintsFootnote = "Check this if you ever doubt that a file really came from your partner."
    static let sameOnBoth = "Same on both phones"
    static let theyAreDifferent = "They are different"
    static let fingerprintsDifferTitle = "The fingerprints differ"
    static let fingerprintsDifferBody = "These phones are not paired with each other as you think. Unpair on both phones, then pair again side by side."
    static let fingerprintsMatch = "Fingerprints match"
    static let howRecoveryWorksBody = [
        "When you pair, each phone can hand the other a recovery copy: your vault key, encrypted so only your partner's phone can open it.",
        "If you lose your phone, pair the new one with your partner and they send your recovery copy back. Your vault key unlocks your notes again: those in an iPhone backup of this app, and everything you shared, which your partner still has.",
        "The recovery copy is your key, not your notes. Notes you never shared and never backed up can't come back from your partner.",
        "Your partner can recover your vault. This is by design.",
    ]
    static let unpairFromPartner = "Unpair from your partner?"
    static let unpairP5Message = "Exchanges stop. Notes you already shared stay on both phones. You can no longer recover your vault from their phone, and their phone keeps your old recovery copy until they unpair too."
    static let typeUnpair = "Type UNPAIR to confirm"
    static let unpairWord = "UNPAIR"
    static let noPartnerYet = "No partner yet"
    static let pairOnce = "Pair once, side by side"
    static let afterPairingBody = "After pairing you can exchange notes and recover each other's vault."
    static let howPairingWorks = "How pairing works"
    static let pairingStep1 = "One phone shows a code"
    static let pairingStep2 = "The other phone scans it"
    static let pairingStep3 = "You both check six digits match"
    static let noAccountFootnote = "No account, no internet. The pairing lives only on your two phones."
    static let whichPhone = "Which phone are you?"
    static let showMyCode = "Show my code"
    static let scanTheirCodeChoice = "Scan my partner's code"
    static let recoveryCopyUpdated = "Recovery copy updated"
    static let recoveryCopyUpdatedBody = "Your partner's phone checked it and keeps it. You can each recover the other's vault."
    static let recoveryCopyRefused = "Your partner's phone did not keep it"
    static let recoveryCopyRefusedBody = "It did not pass the check there. Make sure you are paired with each other, then try again."
    static let sendingRecoveryCopy = "Sending your recovery copy"
    static let partnerRecoveryKept = "Your partner's recovery copy is updated on this phone."
    // Board X1 to X4: the Exchange tab with its exchange area.
    static let withYourPartner = "With your partner"
    static func lastExchange(_ date: Date) -> String { "Last exchange \(date.formatted(.dateTime.month(.abbreviated).day()))" }
    static let pairedPill = "Paired"
    static let notPairedPill = "Not paired"
    static func toSendChip(_ count: Int) -> String { "\(count) to send" }
    static func waitingChip(_ count: Int) -> String { "\(count) waiting" }
    static func notConfirmedChip(_ count: Int) -> String { "\(count) not confirmed" }
    static func nearbyCaption(notConfirmed: Int) -> String {
        guard notConfirmed > 0 else { return "Phone to phone, encrypted. No internet, no server." }
        return notConfirmed == 1
            ? "Phone to phone, encrypted. Also confirms the note sent earlier."
            : "Phone to phone, encrypted. Also confirms the \(notConfirmed) notes sent earlier."
    }
    static let nothingToSendCaption = "Nothing to send. You can still receive."
    static let fileOptionSub = "AirDrop, Messages or Files. Confirmed later."
    static let addNotesFirst = "Add notes to send first"
    static func toSendSection(_ count: Int) -> String { count == 0 ? "To send" : "To send · \(count)" }
    static let addNotes = "Add notes"
    static let addNotesToSend = "Add notes to send"
    static let sentAsFileNotConfirmed = "Sent as a file, not confirmed"
    static func waitingSection(_ count: Int) -> String { count == 0 ? "Waiting for you" : "Waiting for you · \(count)" }
    static let openAFile = "Open a file"
    static let fileFromPartner = "File from your partner"
    static func itemsSuffix(_ count: Int) -> String { count == 1 ? "· 1 item" : "· \(count) items" }
    static let review = "Review"
    static let history = "History"
    static func historySummary(_ entry: ExchangeLogEntry) -> String {
        let date = entry.date.formatted(.dateTime.month(.abbreviated).day())
        return switch entry.direction {
        case .sent: "Sent \(entry.itemCount) · \(date)"
        case .received: "Received \(entry.itemCount) · \(date)"
        case .declined: "Declined · \(date)"
        }
    }
    static let pairFirstTitle = "Pair with your partner first"
    static let pairFirstSub = "Exchange only works between two paired iPhones"
    static let pairFirstBody = "It takes about a minute, side by side. After that, this is where you exchange."
    static let pairNow = "Pair now"
    static let gotAFileAlready = "Got a file from your partner already? Pair first, then open it again."
    static let searchNotes = "Search notes"
    static let alreadyShared = "Already shared"
    static func sealNotes(_ count: Int) -> String { count == 1 ? "Seal 1 note" : "Seal \(count) notes" }
    static let sealingSendsNothing = "Sealing sends nothing. It readies notes for your next exchange."
    // Board F2, as a drill-in from the To send row.
    static func sentAsFileF2Banner(_ date: Date?) -> String {
        let when = date.map { "Sent \($0.formatted(date: .abbreviated, time: .shortened)). " } ?? ""
        return when + "This iPhone can't see whether your partner opened it. Your next nearby exchange confirms it, or sends it again if it never arrived."
    }
    static let notConfirmed = "Not confirmed"
    static let exchangeNearbyToConfirm = "Exchange nearby to confirm"
    // Boards R1 to R3: a file from AirDrop or Messages; the review is shared with N3.
    static let aFileFromPartner = "A file from your partner"
    static let unlockToCheck = "Unlock to check it and see what is inside. Nothing is imported until you accept."
    static func partnerSentYou(_ count: Int) -> String { count == 1 ? "Your partner sent you 1 item" : "Your partner sent you \(count) items" }
    static func sourceFile(_ date: Date) -> String { "Sent as a file · \(date.formatted(date: .abbreviated, time: .shortened)) · verified" }
    static let sourceNearby = "Nearby · from your partner's iPhone · verified"
    static let changedOnBoth = "Changed on both"
    static func changedOnBothNote(_ titles: [String]) -> String {
        titles.count == 1
            ? "You see titles only until you accept. \(titles[0]) changed on both phones, so you will choose which to keep."
            : "You see titles only until you accept. \(titles.count) notes changed on both phones, so you will choose which to keep."
    }
    static let decideLater = "Decide later"
    static let keptForLater = "Kept in Waiting for you"
    static let fileDeclined = "Declined. The file was removed from this iPhone."
    static func itemsAdded(_ count: Int) -> String { count == 1 ? "1 item added" : "\(count) items added" }
    static let fileRemoved = "The file itself has been removed from this iPhone."
    static let confirmedAfterNearby = "Your partner sees these as confirmed after your next nearby exchange."
    static let outcomeAdded = "Added"
    static let outcomeUpdated = "Updated"
    static let outcomeKeptBoth = "Kept both"
    static let outcomeKeptYours = "Kept yours"
    static let outcomeReplaced = "Replaced"
    static let outcomeAlreadyHere = "Already here"
    // Board N2 and N5 additions.
    static let notReceived = "Not received"
    static func untickToKeepWithNotReceived(_ count: Int) -> String {
        count == 1
            ? "Your sealed notes, plus 1 note you sent as a file that never arrived. Untick any you want to keep back. Nothing else leaves this iPhone."
            : "Your sealed notes, plus \(count) notes you sent as a file that never arrived. Untick any you want to keep back. Nothing else leaves this iPhone."
    }
    static let earlierFileSendsConfirmed = "Earlier file sends confirmed"
    // Boards N0 to N5: Exchange nearby.
    static let exchangeNearby = "Exchange nearby"
    static let exchangeSideBySide = "Exchange side by side"
    static let nearbyPrimerBody = "The two phones talk directly, with no internet and no server. iOS will ask you to allow local network access."
    static let nearbyOnlyWhileOpen = "Only looks while this screen is open"
    static let nearbyOnlyPartner = "Only your paired partner's iPhone can connect"
    static let nearbyRadios = "Wi-Fi and Bluetooth must be on. No Wi-Fi network is needed"
    static let sendAsFileInstead = "Send as a file instead"
    static let lookingForPartner = "Looking for your partner's iPhone"
    static let lookingHint = "On your partner's phone: open Exchange, then Exchange nearby. Keep both phones unlocked and close together."
    static let randomCodeOnly = "Nearby devices see only a random code, never your name or your partner's."
    static let end = "End"
    static func connectedTo(_ fingerprint: String) -> String { "Connected to your partner · …\(fingerprint.suffix(4))" }
    static let sendToPartner = "Send to your partner"
    static let untickToKeep = "Your sealed notes. Untick any you want to keep back. Nothing else leaves this iPhone."
    static let partnerCanSendToo = "Your partner can send to you in the same session."
    static let nothingSealedNearby = "Nothing sealed. Seal a note to send it, or wait for your partner to send."
    static func sendItems(_ count: Int) -> String { count == 1 ? "Send 1 item" : "Send \(count) items" }
    static func partnerWantsToSend(_ count: Int) -> String {
        count == 1 ? "Your partner wants to send you 1 item" : "Your partner wants to send you \(count) items"
    }
    static let updatesYours = "Updates yours"
    static let titlesUntilAccept = "You see titles only until you accept. Nothing is added to your vault if you decline."
    static let waitingForPartner = "Waiting for your partner to accept"
    static let partnerAccepted = "Your partner accepted"
    static func sendingItems(_ count: Int) -> String { count == 1 ? "Sending 1 item" : "Sending \(count) items" }
    static let encryptedChecked = "Encrypted on this iPhone. Your partner's phone checks it before importing."
    static let stopNothingImported = "If you stop now, nothing is imported on your partner's phone."
    static let stop = "Stop"
    static let deliveredAndAccepted = "Delivered and accepted"
    static func partnerHasAll(_ count: Int) -> String {
        count == 1 ? "Your partner has the item. It is now marked Shared." : "Your partner has all \(count) items. They are now marked Shared."
    }
    static let sent = "Sent"
    static let received = "Received"
    static let conflicts = "Conflicts"
    static let noneWord = "None"
    static let stayConnected = "Stay connected to receive"
    static let doneEndsSession = "Done ends the session and stops the phone looking for others."
    static let partnerDeclinedTitle = "Your partner declined"
    static let partnerDeclinedBody = "Nothing was added to their vault. Your notes stay Sealed; send again when you are both ready."
    static func confirmedEarlier(_ count: Int) -> String {
        count == 1 ? "1 note you sent as a file is now confirmed." : "\(count) notes you sent as a file are now confirmed."
    }
    static let localNetworkOffTitle = "Local network access is off"
    static let localNetworkOffBody = "Exchange nearby needs it to find your partner's iPhone. Turn it on in Settings, or send as a file."
    static let nearbyUnavailableTitle = "Exchange nearby isn't available"
    static let nearbyUnavailableBody = "Turn on Wi-Fi and Bluetooth, keep both phones unlocked, then try again. No Wi-Fi network is needed."
    static let sessionEnded = "The session ended"
    static let sessionEndedBody = "The phones are no longer connected. Anything accepted before is in place; anything not yet accepted was not sent."
    static let notYourPartnerTitle = "That isn't your partner's iPhone"
    static let notYourPartnerBody = "Only the phone you paired with can exchange with this one. Nothing was sent."
    static let confirmNearbyNow = "Confirm nearby now"
    // Boards F1, F2: Send as a file, the fallback for when the phones are not side by side.
    static let sendAsFile = "Send as a file"
    static let sendAsFileBody = "For when you are not side by side. The file is encrypted so only your partner's iPhone can open it."
    static let fileStep1 = "Choose AirDrop, Messages or Files"
    static let fileStep2 = "With AirDrop, pick your partner's iPhone"
    static let fileStep3 = "They open the file and review it in the app"
    static let cantSeeArrival = "This app can't see whether the file arrived. It is confirmed the next time you exchange nearby."
    static let createEncryptedFile = "Create encrypted file"
    static let sentNotConfirmed = "Sent · not confirmed"
    static let sentNotConfirmedVoiceOver = "Sent as a file. Not confirmed by your partner's phone yet."
    static func sentAsFileBanner(_ date: Date?) -> String {
        let when = date.map { " \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ""
        return "Sent as a file\(when.isEmpty ? "" : ",")\(when). Shown as confirmed once your partner's phone says it accepted them."
    }
    static let sendFileAgain = "Send the file again"
    static let toastFileHandedOver = "File handed over"
    static let packageNotMade = "The encrypted file could not be made. Nothing was sent and nothing changed."
    static let sentNotRecorded = "The file was handed over, but this iPhone could not mark the notes as sent. They are still Sealed."
    static func sentItems(_ count: Int) -> String { count == 1 ? "Sent 1 item" : "Sent \(count) items" }
    static func receivedItems(_ count: Int) -> String { count == 1 ? "Received 1 item" : "Received \(count) items" }
    // Boards 9, U4, 10, 9a to 9d (cycle 5).
    static let fromYourPartner = "From your partner"
    static func verifiedLine(_ date: Date, count: Int) -> String {
        "Verified · \(date.formatted(date: .abbreviated, time: .shortened)) · \(count == 1 ? "1 item" : "\(count) items")"
    }
    static func newSection(_ count: Int) -> String { "\(count) new" }
    static func updateSection(_ count: Int) -> String { count == 1 ? "1 update to a note you have" : "\(count) updates to notes you have" }
    static func conflictSection(_ count: Int) -> String { count == 1 ? "1 changed on both phones" : "\(count) changed on both phones" }
    static func unchangedSection(_ count: Int) -> String { count == 1 ? "1 you already have" : "\(count) you already have" }
    static let titlesOnly = "Titles only. Nothing is added to your vault until you accept."
    static func conflictsToChoose(_ count: Int) -> String {
        count == 1 ? "1 item changed on both phones: you will choose which to keep."
            : "\(count) items changed on both phones: you will choose which to keep."
    }
    static let updatesReplace = "Notes you haven't changed since the last exchange are replaced by your partner's version."
    static func acceptItems(_ count: Int) -> String { count == 1 ? "Accept 1 item" : "Accept \(count) items" }
    static let decline = "Decline"
    static func conflictCounter(_ index: Int, _ count: Int) -> String { "\(index) of \(count) · Changed on both phones" }
    static let yours = "Yours"
    static let partners = "Partner's"
    static func editedAgo(_ date: Date) -> String { "Edited \(date.formatted(.relative(presentation: .named)))" }
    static func lineCount(_ count: Int) -> String { count == 1 ? "1 line" : "\(count) lines" }
    static let keepMine = "Keep mine"
    static let keepPartners = "Keep partner's"
    static let keepBothAsCopy = "Keep both as copy"
    static func keepingBothAdds(_ title: String) -> String { "Keeping both adds \"\(partnersCopy(title))\". Nothing is discarded silently." }
    static func itemsImported(_ count: Int) -> String { count == 1 ? "1 item imported" : "\(count) items imported" }
    static let importNotSaved = "The items could not be saved. Nothing was imported. Try again."
    static let cantBeOpened = "This file can't be opened"
    static let cantBeOpenedBody = "It was changed or damaged after it was sent, so the check that proves it came from your partner failed."
    static let nothingImported = "Nothing was imported."
    static let cantBeOpenedFootnote = "Expecting a file from your partner? It may have been cut short while copying: ask them to send it again. Not expecting one? Delete it."
    static let forDifferentIPhone = "This file is for a different iPhone"
    static let forDifferentIPhoneBody = "It was encrypted for another device, so this iPhone can't read it."
    static let forDifferentIPhoneHint = "This usually means your partner sent it before you paired again on a new phone. Ask them to seal it and send it again."
    static let updateTheApp = "Update the app to open this"
    static let updateTheAppBody = "Your partner's app is newer than yours. Update Between Vault, then open the file again."
    static let openAppStore = "Open App Store"
    static let later = "Later"
    static let youAlreadyHaveThis = "You already have this"
    static func importedOn(_ date: Date?) -> String {
        guard let date else { return "You imported this exact file before. Opening it again changes nothing." }
        return "You imported this exact file on \(date.formatted(date: .abbreviated, time: .shortened)). Opening it again changes nothing."
    }
    static let seeHistory = "See history"
    static let unknownFile = "Between Vault opens files your partner sends from their Between Vault: exchange packages and recovery files. Nothing was changed."
    static let close = "Close"
    static let pairFirstToOpen = "Pair with your partner first. A file from them only opens on their paired iPhone."
    static let emptyPackage = "This file has no notes in it. Nothing was imported."
    static func declinedFiles(_ count: Int) -> String { "Declined 1 file" }
    static func keptBoth(_ count: Int) -> String { count == 1 ? "1 conflict, kept both" : "\(count) conflicts, kept both" }
    static let fromPartnerLabel = "From your partner"
    /// Board 10's naming for Keep both.
    static func partnersCopy(_ title: String) -> String { "\(title) (partner's copy)" }
    static let historyFooter = "This log keeps counts and dates only. No titles, no content."

    // MARK: Partner

    static let fingerprint = "Fingerprint"
    static let partnerCanRecover = "Your partner can recover your vault. This is by design."
    static let unpairPartner = "Unpair partner"
    // Board 14.
    static let paired = "Paired"
    static func since(_ date: Date) -> String { "Since \(date.formatted(.dateTime.month(.abbreviated).year()))" }
    static let deviceFingerprint = "Device fingerprint"
    static let alsoNewPhone = "It is also how you get your data back on a new phone."
    static let sendRecoveryFile = "Send recovery file to partner"
    static let compareFingerprintAgain = "Compare fingerprint again"
    static let unpairFootnote = "Asks twice. Unpairing stops future exchanges. Items already shared stay on both phones."
    // Not on a board: the second look at the fingerprint, and the two unpair asks.
    static let compareFingerprintBody = "Hold both phones side by side. Partner, then Compare fingerprint again on theirs. Every character should be the same."
    static let unpairTitle = "Unpair partner?"
    static let unpairMessage = "Unpairing stops future exchanges. Items already shared stay on both phones."
    static let unpairAgainTitle = "Unpair for good?"
    /// Honest about the limit: a recovery file already sent stays on the partner's phone and still
    /// opens this vault; unpairing cannot reach it offline.
    static let unpairAgainMessage = "You no longer hold your partner's recovery file. A recovery file you already sent stays on their phone and can still open this vault. Pairing again needs both phones side by side."
    static let unpair = "Unpair"
    static let unpairFailed = "Unpairing did not finish. Try again."
    static let recoveryFileNotMade = "The recovery file could not be made. Nothing was sent."
    // Opening a recovery file from the partner.
    static let recoverySavedTitle = "Recovery file saved"
    static let recoverySaved = "If your partner loses their iPhone, you can help them restore their vault."
    static let recoveryNotSavedTitle = "Recovery file not saved"
    static let recoveryNotPaired = "Pair first. A recovery file only opens on the partner it was made for."
    static let recoveryNotForThisPairing = "This recovery file is not from your paired partner, or not for this iPhone. Nothing was saved."
    static let recoveryUnreadable = "This file could not be read. Nothing was saved."
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
    // Pairing progress (owner feedback from the two phone test: too static, unclear whose turn).
    static let scanTheirCode = "Scan your partner's code"
    static let compareCodes = "Compare the codes"
    static let youShow = "You show"
    static let youScan = "You scan"
    static let bothCompare = "Both compare"
    static let partnerScansThis = "Hold your phone up. Your partner scans this screen with Between Vault."
    static let whenTheyveScanned = "When their screen changes, tap below."
    static let pointAtTheirScreen = "Point the camera at your partner's screen. It moves on by itself."
    static let scanned = "Scanned"
    static func progressLabel(_ index: Int, _ count: Int, _ action: String) -> String { "Step \(index) of \(count): \(action)" }
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
    // App icon picker: the two directions of the "App icon concepts" board.
    static let appIcon = "App icon"
    static let iconTwoOfYou = "Two of you"
    static let iconVaultDoor = "Vault door"
    static let iconFooter = "Changes the icon on your Home Screen. iOS confirms the change."
    static let iconNotChanged = "The icon could not be changed. Try again."
    static let version = "Version"
    static let collectsNothing = "This app collects nothing and has no server to send it to."
}
