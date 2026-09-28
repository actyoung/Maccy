import SwiftUI
import Defaults
import Settings

struct StorageSettingsPane: View {
  @Observable
  class ViewModel {
    var saveFiles = false {
      didSet {
        Defaults.withoutPropagation {
          if saveFiles {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.files.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.files.types)
          }
        }
      }
    }

    var saveImages = false {
      didSet {
        Defaults.withoutPropagation {
          if saveImages {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.images.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.images.types)
          }
        }
      }
    }

    var saveText = false {
      didSet {
        Defaults.withoutPropagation {
          if saveText {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.text.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.text.types)
          }
        }
      }
    }

    private var observer: Defaults.Observation?

    init() {
      observer = Defaults.observe(.enabledPasteboardTypes) { change in
        self.saveFiles = change.newValue.isSuperset(of: StorageType.files.types)
        self.saveImages = change.newValue.isSuperset(of: StorageType.images.types)
        self.saveText = change.newValue.isSuperset(of: StorageType.text.types)
      }
    }

    deinit {
      observer?.invalidate()
    }
  }

  @Default(.size) private var size
  @Default(.sortBy) private var sortBy
  @Default(.historyRetentionDays) private var historyRetentionDays

  @State private var viewModel = ViewModel()
  @State private var persistentHistoryEnabled = Defaults[.persistentHistoryEnabled]
  @State private var persistenceError: String?
  @State private var showingDeleteConfirmation = false
  @State private var storageSize = Storage.shared.size

  private let sizeFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 999
    return formatter
  }()

  private let retentionFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 365
    return formatter
  }()

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(
        bottomDivider: true,
        label: { Text("Save", tableName: "StorageSettings") }
      ) {
        Toggle(
          isOn: $viewModel.saveFiles,
          label: { Text("Files", tableName: "StorageSettings") }
        )
        Toggle(
          isOn: $viewModel.saveImages,
          label: { Text("Images", tableName: "StorageSettings") }
        )
        Toggle(
          isOn: $viewModel.saveText,
          label: { Text("Text", tableName: "StorageSettings") }
        )
        Text("SaveDescription", tableName: "StorageSettings")
          .controlSize(.small)
          .foregroundStyle(.gray)
      }

      Settings.Section(
        bottomDivider: true,
        label: { text("EncryptedHistory", defaultValue: "Encrypted history:") }
      ) {
        Toggle(
          isOn: Binding(
            get: { persistentHistoryEnabled },
            set: updatePersistence
          ),
          label: { text("EncryptedHistoryEnabled", defaultValue: "Keep history on this Mac") }
        )

        HStack {
          TextField("", value: $historyRetentionDays, formatter: retentionFormatter)
            .frame(width: 60)
          Stepper("", value: $historyRetentionDays, in: 1...365)
            .labelsHidden()
          text("Days", defaultValue: "days")
        }
        .onChange(of: historyRetentionDays) {
          History.shared.pruneExpired()
          storageSize = Storage.shared.size
        }

        text(
          "EncryptedHistoryDescription",
          defaultValue: "Items are encrypted before being written to disk. " +
            "Turning this off pauses disk writes; existing encrypted data and its Keychain key are kept for reuse."
        )
        .controlSize(.small)
        .foregroundStyle(.gray)

        Button(role: .destructive) {
          showingDeleteConfirmation = true
        } label: {
          text("DeleteEncryptedHistory", defaultValue: "Delete encrypted history and key")
        }
      }

      Settings.Section(label: { Text("Size", tableName: "StorageSettings") }) {
        HStack {
          TextField("", value: $size, formatter: sizeFormatter)
            .frame(width: 80)
            .help(Text("SizeTooltip", tableName: "StorageSettings"))
          Stepper("", value: $size, in: 1...999)
            .labelsHidden()
          Text(storageSize)
            .controlSize(.small)
            .foregroundStyle(.gray)
            .help(Text("CurrentSizeTooltip", tableName: "StorageSettings"))
            .onAppear {
              persistentHistoryEnabled = Defaults[.persistentHistoryEnabled]
              storageSize = Storage.shared.size
            }
        }
      }

      Settings.Section(label: { Text("SortBy", tableName: "StorageSettings") }) {
        Picker("", selection: $sortBy) {
          ForEach(Sorter.By.allCases) { mode in
            Text(mode.description)
          }
        }
        .labelsHidden()
        .frame(width: 160, alignment: .leading)
        .help(Text("SortByTooltip", tableName: "StorageSettings"))
      }
    }
    .confirmationDialog(
      localized(
        "DeleteEncryptedHistoryConfirmation",
        defaultValue: "Delete all encrypted history and its encryption key?"
      ),
      isPresented: $showingDeleteConfirmation
    ) {
      Button(
        localized("DeleteEncryptedHistory", defaultValue: "Delete encrypted history and key"),
        role: .destructive,
        action: deletePersistentHistory
      )
      Button(localized("Cancel", defaultValue: "Cancel"), role: .cancel) {}
    } message: {
      text(
        "DeleteEncryptedHistoryWarning",
        defaultValue: "This cannot be undone. " +
          "The history currently held in memory will remain available until Maccy quits."
      )
    }
    .alert(
      localized("EncryptedHistoryError", defaultValue: "Encrypted history error"),
      isPresented: Binding(
        get: { persistenceError != nil },
        set: { if !$0 { persistenceError = nil } }
      )
    ) {
      Button(localized("OK", defaultValue: "OK")) {
        persistenceError = nil
      }
    } message: {
      Text(verbatim: persistenceError ?? "")
    }
  }

  private func updatePersistence(_ enabled: Bool) {
    do {
      try Storage.shared.setPersistenceEnabled(enabled)
      persistentHistoryEnabled = enabled
      storageSize = Storage.shared.size
      Task {
        try? await History.shared.load()
      }
    } catch {
      persistentHistoryEnabled = Defaults[.persistentHistoryEnabled]
      persistenceError = error.localizedDescription
      storageSize = Storage.shared.size
    }
  }

  private func deletePersistentHistory() {
    do {
      try Storage.shared.deletePersistentHistoryAndKey()
      persistentHistoryEnabled = false
      storageSize = Storage.shared.size
    } catch {
      persistentHistoryEnabled = Defaults[.persistentHistoryEnabled]
      persistenceError = error.localizedDescription
      storageSize = Storage.shared.size
    }
  }

  private func text(_ key: String, defaultValue: String) -> Text {
    Text(verbatim: localized(key, defaultValue: defaultValue))
  }

  private func localized(_ key: String, defaultValue: String) -> String {
    NSLocalizedString(
      key,
      tableName: "StorageSettings",
      bundle: .main,
      value: defaultValue,
      comment: ""
    )
  }
}

#if DEBUG
#Preview {
  StorageSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
#endif
