import SwiftUI
import CoreLocation

struct CourseSearchView: View {
    let courseSearch: CourseSearchService
    let locationService: LocationService
    let onCourseLoaded: (Course) -> Void
    let onCourseWithTeeLoaded: ((Course, String) -> Void)?
    let onSkip: () -> Void

    @State private var query = ""
    @State private var results: [CourseSearchResult] = []
    @State private var searching = false
    @State private var loadingId: String?
    @State private var error: String?
    @State private var loadedCourse: Course?
    @State private var showTeeSelection = false

    init(courseSearch: CourseSearchService, locationService: LocationService,
         onCourseLoaded: @escaping (Course) -> Void,
         onCourseWithTeeLoaded: ((Course, String) -> Void)? = nil,
         onSkip: @escaping () -> Void) {
        self.courseSearch = courseSearch
        self.locationService = locationService
        self.onCourseLoaded = onCourseLoaded
        self.onCourseWithTeeLoaded = onCourseWithTeeLoaded
        self.onSkip = onSkip
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Find Your Course")
                    .font(.title3.bold())
                Text("Search to auto-load hole data and GPS maps")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Search by name
            HStack(spacing: 8) {
                TextField("Course name...", text: $query)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .submitLabel(.search)
                    .onSubmit { searchByName() }

                Button { searchByName() } label: {
                    Text(searching ? "..." : "Search")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Search nearby
            Button {
                searchNearby()
            } label: {
                HStack {
                    Image(systemName: "location.fill")
                    Text(searching ? "Finding courses..." : "Find courses near me")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(searching)

            // Results
            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(results.count) course\(results.count == 1 ? "" : "s") found")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(results) { result in
                        Button {
                            loadCourse(result)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name).font(.subheadline.bold())
                                    if let city = result.city, let state = result.state {
                                        Text("\(city), \(state)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if loadingId == result.id {
                                    ProgressView().tint(.green)
                                }
                            }
                            .padding(12)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(loadingId != nil)
                    }
                }
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button("Set up course manually") {
                onSkip()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showTeeSelection) {
            if let course = loadedCourse {
                teeSelectionSheet(course)
            }
        }
    }

    private func searchByName() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true
        error = nil
        results = []

        Task {
            do {
                let found = try await courseSearch.searchByName(query)
                await MainActor.run {
                    results = found
                    if found.isEmpty { error = "No courses found. Try a different name." }
                    searching = false
                }
            } catch let searchError {
                await MainActor.run {
                    self.error = searchError.localizedDescription
                    searching = false
                }
            }
        }
    }

    private func searchNearby() {
        searching = true
        error = nil
        results = []

        guard let loc = locationService.location else {
            locationService.requestPermission()
            error = "Enable location access to search nearby."
            searching = false
            return
        }

        Task {
            do {
                let found = try await courseSearch.searchNearby(lat: loc.latitude, lng: loc.longitude)
                await MainActor.run {
                    results = found
                    if found.isEmpty { error = "No courses found nearby." }
                    searching = false
                }
            } catch let searchError {
                await MainActor.run {
                    self.error = searchError.localizedDescription
                    searching = false
                }
            }
        }
    }

    private func loadCourse(_ result: CourseSearchResult) {
        loadingId = result.id
        error = nil

        Task {
            do {
                let details = try await courseSearch.fetchCourseDetails(id: result.id)
                let course = Course(
                    id: result.id,
                    name: details.name,
                    city: details.city,
                    state: details.state,
                    location: details.location,
                    tees: details.tees
                )
                await MainActor.run {
                    loadingId = nil
                    if course.tees.count > 1 && onCourseWithTeeLoaded != nil {
                        loadedCourse = course
                        showTeeSelection = true
                    } else {
                        onCourseLoaded(course)
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to load course details"
                    loadingId = nil
                }
            }
        }
    }

    private func teeSelectionSheet(_ course: Course) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Select Tees")
                    .font(.title3.bold())
                    .padding(.top, 8)

                Text(course.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(course.tees) { tee in
                    Button {
                        showTeeSelection = false
                        onCourseWithTeeLoaded?(course, tee.name)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tee.name)
                                    .font(.headline)
                                if let rating = tee.rating, let slope = tee.slope {
                                    Text("Rating \(String(format: "%.1f", rating)) / Slope \(slope)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let totalYardage = tee.holes.compactMap(\.yardage).reduce(0, +) as Int?,
                                   totalYardage > 0 {
                                    Text("\(totalYardage) yards")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showTeeSelection = false
                        loadedCourse = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
