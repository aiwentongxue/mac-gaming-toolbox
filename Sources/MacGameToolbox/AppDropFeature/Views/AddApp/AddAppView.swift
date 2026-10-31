import SwiftUI
import AppDropCore

/// Adds apps either by pasting an App Store link or by searching a storefront.
struct AddAppView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable {
        case link
        case search
    }

    @State private var mode: Mode = .search

    // Link mode
    @State private var linkText = ""
    @State private var parsedLink: ParsedAppStoreLink?
    @State private var linkError: String?
    @State private var addingFromLink = false

    // Search mode
    @State private var searchKeyword = ""
    @State private var searchCountry: String = SharedConstants.defaultCountryCode
    @State private var searchPlatform: AppStoreSearchPlatform = .macOS
    @State private var results: [AppStoreApp] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var hasSearched = false
    @State private var addingTrackId: String?

    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppStrings.string("add.title"))
                .font(.title3.weight(.semibold))
            Picker("", selection: $mode) {
                Text(AppStrings.string("add.tab.link")).tag(Mode.link)
                Text(AppStrings.string("add.tab.search")).tag(Mode.search)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .link:
                linkSection
            case .search:
                searchSection
            }

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(AppStrings.string("common.close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420, alignment: .topLeading)
        .onAppear {
            searchCountry = environment.defaultCountryCode
        }
    }

    // MARK: - Link mode

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(AppStrings.string("add.link.placeholder"), text: $linkText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { parseLink() }
            HStack(spacing: 10) {
                Button(AppStrings.string("add.link.parse")) { parseLink() }
                if let parsedLink {
                    Text("\(AppStrings.regionLabel(parsedLink.countryCode)) · id\(parsedLink.trackId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let linkError {
                Text(linkError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let parsedLink {
                Button {
                    addFromLink(parsedLink)
                } label: {
                    if addingFromLink {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(AppStrings.string("add.action"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(addingFromLink)
            }
            Spacer(minLength: 0)
        }
    }

    private func parseLink() {
        linkError = nil
        parsedLink = nil
        switch AppStoreURLParser.parse(linkText) {
        case .success(let parsed):
            parsedLink = parsed
        case .failure(let error):
            linkError = AppStrings.errorDescription(error)
        }
    }

    private func addFromLink(_ parsed: ParsedAppStoreLink) {
        addingFromLink = true
        message = nil
        Task {
            let outcome = await environment.addTrackedApp(parsedLink: parsed)
            addingFromLink = false
            apply(outcome: outcome)
        }
    }

    // MARK: - Search mode

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker(AppStrings.string("add.region"), selection: $searchCountry) {
                    ForEach(SharedConstants.supportedCountryCodes, id: \.self) { code in
                        Text(AppStrings.regionLabel(code)).tag(code)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 210)
                Picker(AppStrings.string("add.platform"), selection: $searchPlatform) {
                    Text(AppStrings.string("add.platform.mac")).tag(AppStoreSearchPlatform.macOS)
                    Text(AppStrings.string("add.platform.ios")).tag(AppStoreSearchPlatform.iOS)
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                TextField(AppStrings.string("add.search.placeholder"), text: $searchKeyword)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { performSearch() }
                Button(AppStrings.string("add.search.button")) { performSearch() }
                    .disabled(isSearching || searchKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                if isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            if let searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if hasSearched && !isSearching && !resultsMatchSearchTerm {
                indexGapNotice
            }
            List(results) { result in
                HStack(spacing: 10) {
                    TrackedAppIconView(artworkURL: result.artworkURL, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name).lineLimit(1)
                        Text(result.developerName ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(result.formattedPrice ?? AppStrings.string("card.pendingPrice"))
                            .font(.callout.weight(.medium))
                        HStack(spacing: 4) {
                            PlatformBadge(platform: result.platform)
                            RegionBadge(countryCode: searchCountry)
                        }
                    }
                    Button {
                        addFromSearch(result)
                    } label: {
                        if addingTrackId == result.trackId {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(AppStrings.string("common.add"))
                        }
                    }
                    .disabled(addingTrackId != nil)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
            .frame(minHeight: 220)
        }
    }

    private func performSearch() {
        let keyword = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        isSearching = true
        searchError = nil
        Task {
            do {
                results = try await environment.fetcher.search(
                    keyword: keyword,
                    country: searchCountry,
                    platform: searchPlatform
                )
            } catch {
                results = []
                searchError = AppStrings.errorDescription(error)
            }
            hasSearched = true
            isSearching = false
        }
    }

    /// True when at least one result's name contains the searched term. Apple's
    /// search index misses some apps (notably recently released Mac games), so a
    /// list of fuzzy, unrelated matches is a strong "not in the index" signal.
    private var resultsMatchSearchTerm: Bool {
        let term = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        return results.contains { $0.name.localizedCaseInsensitiveContains(term) }
    }

    private var indexGapNotice: some View {
        VStack(spacing: 8) {
            if results.isEmpty {
                Text(AppStrings.string("add.search.noResults"))
                    .foregroundStyle(.secondary)
            } else {
                Text(AppStrings.format("add.search.noExactMatch", searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines)))
                    .foregroundStyle(.secondary)
            }
            Text(AppStrings.string("add.search.indexGapHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(AppStrings.string("add.search.switchToLink")) {
                mode = .link
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
    }

    private func addFromSearch(_ result: AppStoreApp) {
        addingTrackId = result.trackId
        message = nil
        Task {
            let outcome = await environment.addTrackedApp(searchResult: result, country: searchCountry)
            addingTrackId = nil
            apply(outcome: outcome)
        }
    }

    private func apply(outcome: AddTrackedAppOutcome) {
        switch outcome {
        case .added(let name):
            message = AppStrings.format("add.success", name)
        case .duplicate(let name):
            message = AppStrings.format("add.duplicateNamed", name)
        case .failed(let reason):
            message = AppStrings.format("add.failed", reason)
        }
    }
}
