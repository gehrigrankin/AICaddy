import SwiftUI
import SwiftData

/// Manage your golf bag — 14 clubs with swing thoughts and equipment tracking
struct BagView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bags: [GolfBag]
    @Query private var equipmentLogs: [EquipmentLog]

    @State private var editingClub: BagClub?
    @State private var showAddEquipment = false
    @State private var showAddClub = false

    private var bag: GolfBag? { bags.first }

    private var clubsByCategory: [(String, [BagClub])] {
        guard let bag else { return [] }
        let categories: [(String, (Club) -> Bool)] = [
            ("Woods", { [.driver, .wood3, .wood5, .wood7].contains($0) }),
            ("Hybrids", { [.hybrid2, .hybrid3, .hybrid4, .hybrid5].contains($0) }),
            ("Irons", { [.iron2, .iron3, .iron4, .iron5, .iron6, .iron7, .iron8, .iron9].contains($0) }),
            ("Wedges", { [.pw, .gw, .sw, .lw].contains($0) }),
            ("Putter", { $0 == .putter }),
        ]
        return categories.compactMap { (name, filter) in
            let clubs = bag.clubs.filter { filter($0.club) }
            return clubs.isEmpty ? nil : (name, clubs)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header card
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MY BAG")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.green.opacity(0.7))
                            .tracking(1)
                        Text("\(bag?.clubs.count ?? 0) of 14 clubs")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if bag == nil {
                        Button {
                            let newBag = GolfBag()
                            modelContext.insert(newBag)
                        } label: {
                            Text("Set Up Bag")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.green)
                                .clipShape(Capsule())
                        }
                    } else if (bag?.clubs.count ?? 14) < 14 {
                        Button { showAddClub = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Add Club")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.green)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.green.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(14)
                .background(Color(.systemGray6).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // Clubs by category
                if let bag {
                    ForEach(clubsByCategory, id: \.0) { category, clubs in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category.uppercased())
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                                .padding(.leading, 4)

                            VStack(spacing: 1) {
                                ForEach(clubs) { club in
                                    Button { editingClub = club } label: {
                                        HStack(spacing: 12) {
                                            // Club icon
                                            Image(systemName: clubIcon(for: club.club))
                                                .font(.system(size: 14))
                                                .foregroundStyle(.green)
                                                .frame(width: 32, height: 32)
                                                .background(.green.opacity(0.1))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                            // Name + brand
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(club.club.displayName)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(.primary)
                                                if let brand = club.brand, let model = club.model {
                                                    Text("\(brand) \(model)")
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(.secondary)
                                                } else if let brand = club.brand {
                                                    Text(brand)
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(.secondary)
                                                }
                                            }

                                            Spacer()

                                            // Yardage
                                            if let yardage = club.effectiveYardage {
                                                VStack(alignment: .trailing, spacing: 1) {
                                                    Text("\(yardage)")
                                                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                                                        .foregroundStyle(.white)
                                                    Text("YDS")
                                                        .font(.system(size: 8, weight: .bold))
                                                        .foregroundStyle(.secondary)
                                                }
                                            } else {
                                                Text("--")
                                                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                                                    .foregroundStyle(.tertiary)
                                            }

                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                    }
                                }
                            }
                            .background(Color(.systemGray6).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    // Swing thought preview
                    let thoughts = bag.clubs.filter { $0.swingThought != nil && !($0.swingThought?.isEmpty ?? true) }
                    if !thoughts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SWING THOUGHTS")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                                .padding(.leading, 4)

                            VStack(spacing: 6) {
                                ForEach(thoughts) { club in
                                    HStack(spacing: 10) {
                                        Text(club.club.displayName)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.green)
                                            .frame(width: 60, alignment: .leading)
                                        Text(club.swingThought ?? "")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.primary)
                                            .italic()
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                }
                            }
                            .background(Color(.systemGray6).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                // Equipment log
                if !equipmentLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("EQUIPMENT LOG")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                            Spacer()
                            Button { showAddEquipment = true } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.horizontal, 4)

                        VStack(spacing: 1) {
                            ForEach(equipmentLogs.sorted(by: { $0.dateStarted > $1.dateStarted }).prefix(5), id: \.id) { log in
                                HStack(spacing: 10) {
                                    Text(log.itemType.capitalized)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.green.opacity(0.1))
                                        .clipShape(Capsule())
                                    Text(log.itemName)
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text(log.dateStarted.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                        }
                        .background(Color(.systemGray6).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    Button { showAddEquipment = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 14))
                            Text("Log Equipment Change")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6).opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100) // clear tab bar
        }
        .navigationTitle("My Bag")
        .sheet(item: $editingClub) { club in
            EditClubSheet(bag: bag!, club: club, modelContext: modelContext)
        }
        .sheet(isPresented: $showAddEquipment) {
            AddEquipmentSheet(modelContext: modelContext)
        }
        .sheet(isPresented: $showAddClub) {
            if let bag {
                AddClubSheet(bag: bag)
            }
        }
    }
}

private func clubIcon(for club: Club) -> String {
    switch club {
    case .driver: return "figure.golf"
    case .wood3, .wood5, .wood7: return "3.circle.fill"
    case .hybrid2, .hybrid3, .hybrid4, .hybrid5: return "h.circle.fill"
    case .iron2, .iron3, .iron4, .iron5, .iron6, .iron7, .iron8, .iron9: return "number.circle.fill"
    case .pw, .gw, .sw, .lw: return "w.circle.fill"
    case .putter: return "p.circle.fill"
    }
}

struct AddClubSheet: View {
    let bag: GolfBag
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClub: Club?

    private var availableClubs: [Club] {
        let existing = Set(bag.clubs.map(\.club))
        return Club.allCases.filter { !existing.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Club", selection: $selectedClub) {
                    Text("Select a club").tag(Club?.none)
                    ForEach(availableClubs) { club in
                        Text(club.displayName).tag(Club?.some(club))
                    }
                }
            }
            .navigationTitle("Add Club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        if let club = selectedClub {
                            var clubs = bag.clubs
                            clubs.append(BagClub(club: club))
                            bag.clubs = clubs
                        }
                        dismiss()
                    }
                    .bold()
                    .disabled(selectedClub == nil)
                }
            }
        }
    }
}

struct EditClubSheet: View {
    let bag: GolfBag
    let club: BagClub
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss
    @State private var brand: String
    @State private var model: String
    @State private var swingThought: String
    @State private var manualYardageText: String
    @State private var showReplaceSheet = false
    @State private var showDeleteConfirm = false

    init(bag: GolfBag, club: BagClub, modelContext: ModelContext) {
        self.bag = bag
        self.club = club
        self.modelContext = modelContext
        _brand = State(initialValue: club.brand ?? "")
        _model = State(initialValue: club.model ?? "")
        _swingThought = State(initialValue: club.swingThought ?? "")
        _manualYardageText = State(initialValue: club.manualYardage.map { String($0) } ?? "")
    }

    private var availableReplacements: [Club] {
        let existing = Set(bag.clubs.map(\.club))
        return Club.allCases.filter { !existing.contains($0) || $0 == club.club }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Club") {
                    Text(club.club.displayName).font(.headline)
                }

                Section("Details") {
                    TextField("Brand (e.g., Titleist)", text: $brand)
                    TextField("Model (e.g., T200)", text: $model)
                }

                Section("Yardage") {
                    TextField("My typical distance (yards)", text: $manualYardageText)
                        .keyboardType(.numberPad)
                    if let learned = club.learnedAvgYardage, let count = club.learnedShotCount {
                        Text("Tracked avg: \(learned)y (\(count) shots)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Swing Thought") {
                    TextField("e.g., Slow takeaway", text: $swingThought)
                    Text("Shows during play when you select this club")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showReplaceSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Replace with Different Club")
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Remove from Bag")
                        }
                    }
                }
            }
            .navigationTitle("Edit \(club.club.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveAndDismiss() }.bold()
                }
            }
            .confirmationDialog("Remove \(club.club.displayName)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    var clubs = bag.clubs
                    clubs.removeAll { $0.id == club.id }
                    bag.clubs = clubs
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showReplaceSheet) {
                ReplaceClubSheet(bag: bag, oldClub: club, onReplace: { newClubType in
                    var clubs = bag.clubs
                    if let idx = clubs.firstIndex(where: { $0.id == club.id }) {
                        clubs[idx] = BagClub(club: newClubType)
                    }
                    bag.clubs = clubs
                    dismiss()
                })
            }
        }
    }

    private func saveAndDismiss() {
        var clubs = bag.clubs
        if let idx = clubs.firstIndex(where: { $0.id == club.id }) {
            let parsedYardage = Int(manualYardageText)
            clubs[idx] = BagClub(
                club: club.club,
                brand: brand.isEmpty ? nil : brand,
                model: model.isEmpty ? nil : model,
                swingThought: swingThought.isEmpty ? nil : swingThought,
                manualYardage: parsedYardage,
                learnedAvgYardage: club.learnedAvgYardage,
                learnedShotCount: club.learnedShotCount
            )
            bag.clubs = clubs
        }
        dismiss()
    }
}

struct ReplaceClubSheet: View {
    let bag: GolfBag
    let oldClub: BagClub
    let onReplace: (Club) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedClub: Club?

    private var availableClubs: [Club] {
        let existing = Set(bag.clubs.map(\.club))
        return Club.allCases.filter { !existing.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Replace \(oldClub.club.displayName) with:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(availableClubs) { club in
                    Button {
                        onReplace(club)
                    } label: {
                        HStack {
                            Text(club.displayName)
                                .font(.subheadline.bold())
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("Replace Club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct AddEquipmentSheet: View {
    let modelContext: ModelContext
    @Environment(\.dismiss) private var dismiss

    @State private var itemType = "ball"
    @State private var itemName = ""
    @State private var club = ""
    @State private var notes = ""

    let types = ["ball", "grip", "shaft", "club", "glove", "other"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $itemType) {
                    ForEach(types, id: \.self) { Text($0.capitalized) }
                }

                TextField("Name (e.g., Pro V1)", text: $itemName)
                TextField("Club (optional)", text: $club)
                TextField("Notes", text: $notes)
            }
            .navigationTitle("Log Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let log = EquipmentLog(
                            itemType: itemType,
                            itemName: itemName,
                            club: club.isEmpty ? nil : club,
                            notes: notes.isEmpty ? nil : notes
                        )
                        modelContext.insert(log)
                        dismiss()
                    }
                    .bold()
                    .disabled(itemName.isEmpty)
                }
            }
        }
    }
}
