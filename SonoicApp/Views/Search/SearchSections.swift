import SwiftUI

struct SearchInputCard: View {
    @Binding var query: String
    @Binding var isFocused: Bool
    let placeholder: String
    let isSearching: Bool
    let hasQuery: Bool
    let submit: () -> Void
    @FocusState private var fieldIsFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .focused($fieldIsFocused)
                    .onSubmit(submit)

                submitButton
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.38), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(fieldIsFocused ? Color.accentColor.opacity(0.65) : Color.white.opacity(0.08), lineWidth: 1)
            }

            if fieldIsFocused || query.sonoicNonEmptyTrimmed != nil {
                Button(action: clearQuery) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Clear search")
            }
        }
        .onChange(of: fieldIsFocused) { _, newValue in
            isFocused = newValue
        }
        .onChange(of: isFocused) { _, newValue in
            if !newValue {
                fieldIsFocused = false
            }
        }
    }

    @ViewBuilder
    private var submitButton: some View {
        if isSearching {
            ProgressView()
                .controlSize(.small)
                .frame(width: 22, height: 22)
        } else if hasQuery {
            Button(action: submit) {
                Image(systemName: "arrow.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Search")
        }
    }

    private func clearQuery() {
        query = ""
    }
}

struct SearchRecentQueriesSection: View {
    let recentSearches: [SonoicRecentSourceSearch]
    let select: (SonoicRecentSourceSearch) -> Void
    let clear: () -> Void

    var body: some View {
        if !recentSearches.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    HomeSectionHeader(
                        title: "Recent"
                    )

                    Spacer(minLength: 0)

                    Button("Clear", action: clear)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                SonoicListCard {
                    SonoicListRows(
                        Array(recentSearches.prefix(5)),
                        dividerLeadingPadding: SonoicTheme.Layout.navigationDividerLeading
                    ) { recentSearch, _ in
                        Button {
                            select(recentSearch)
                        } label: {
                            SearchRecentQueryRow(recentSearch: recentSearch)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Search \(recentSearch.query)")
                    }
                }
            }
        }
    }
}

private struct SearchRecentQueryRow: View {
    let recentSearch: SonoicRecentSourceSearch

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)

            Text(recentSearch.query)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
