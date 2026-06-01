import SwiftUI

struct ContactsView: View {
    @EnvironmentObject private var store: KnotLinkStore
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id
    @State private var lookup = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: copy.t("contacts"), subtitle: copy.t("contactsSubtitle"))

                HStack(spacing: 10) {
                    TextField(copy.t("contactLookupPlaceholder"), text: $lookup)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    Button {
                        store.inviteContact(lookup: lookup)
                        lookup = ""
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .frame(width: 38, height: 38)
                    }
                    .prominentGlassButton()
                }
                .padding(12)
                .glassCard(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: true)

                if !store.incomingInvitations.isEmpty {
                    ContactSectionTitle(copy.t("incomingRequests"))
                    ForEach(store.incomingInvitations) { invitation in
                        InvitationRow(invitation: invitation)
                    }
                }

                ContactSectionTitle(copy.t("yourContacts"))
                LazyVStack(spacing: 12) {
                    if store.contacts.isEmpty {
                        ContentUnavailableView(copy.t("noContactsYet"), systemImage: "person.crop.circle.badge.plus")
                    } else {
                        ForEach(store.contacts) { contact in
                            Button {
                                store.openConversation(with: contact)
                            } label: {
                                HStack(spacing: 14) {
                                    AvatarView(title: contact.displayName, id: contact.id, imageURL: contact.avatarURL)
                                    VStack(alignment: .leading) {
                                        Text(contact.displayName).font(.headline)
                                        Text("@\(contact.username)").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(copy.t("message"))
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.knotSky.opacity(0.14), in: Capsule())
                                }
                                .padding(14)
                            }
                            .buttonStyle(.plain)
                            .glassCard(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
                        }
                    }
                }

                if !store.outgoingInvitations.isEmpty {
                    ContactSectionTitle(copy.t("sentInvitations"))
                    ForEach(store.outgoingInvitations) { invitation in
                        HStack(spacing: 14) {
                            AvatarView(title: invitation.person.displayName, id: invitation.person.id)
                            VStack(alignment: .leading) {
                                Text(invitation.person.displayName).font(.headline)
                                Text("@\(invitation.person.username)").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(copy.t("pending"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .glassCard(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
            }
            .padding()
            .padding(.bottom, 88)
        }
        .navigationTitle(copy.t("contacts"))
        .navigationBarTitleDisplayMode(.inline)
        .background(.clear)
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }
}

private struct ContactSectionTitle: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}

private struct InvitationRow: View {
    @EnvironmentObject private var store: KnotLinkStore
    @AppStorage(AppCopy.languageStorageKey) private var appLanguageCode = AppLanguageOption.english.id
    var invitation: ContactInvitation

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(title: invitation.person.displayName, id: invitation.person.id)
            VStack(alignment: .leading) {
                Text(invitation.person.displayName).font(.headline)
                Text("@\(invitation.person.username)").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 9) {
                Button {
                    store.acceptInvitation(invitation)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.knotBlue.opacity(0.92), in: Circle())
                        .glassCard(tint: Color.knotSky.opacity(0.18), in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copy.t("accept"))

                Button(role: .destructive) {
                    store.declineInvitation(invitation)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.red)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.22), in: Circle())
                        .glassCard(tint: .white.opacity(0.16), in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copy.t("decline"))
            }
        }
        .padding(14)
        .glassCard(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
    }

    private var copy: AppCopy {
        AppCopy(languageCode: appLanguageCode)
    }
}
