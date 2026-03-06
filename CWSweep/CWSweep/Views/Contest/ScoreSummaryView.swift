import SwiftUI

// MARK: - ScoreSummaryView

/// Real-time score breakdown and QSO rate visualization.
struct ScoreSummaryView: View {
    // MARK: Internal

    var body: some View {
        if contestManager.isActive {
            HSplitView {
                // Left: Score table
                VStack(alignment: .leading, spacing: 0) {
                    Text("Score Summary")
                        .font(.headline)
                        .padding()

                    Table(bandBreakdown) {
                        TableColumn("Band") { row in
                            Text(row.band)
                                .fontWeight(row.band == "Total" ? .bold : .regular)
                        }
                        .width(min: 60, ideal: 80)

                        TableColumn("QSOs") { row in
                            Text("\(row.qsos)")
                                .monospacedDigit()
                                .fontWeight(row.band == "Total" ? .bold : .regular)
                        }
                        .width(min: 50, ideal: 60)

                        TableColumn("Points") { row in
                            Text("\(row.points)")
                                .monospacedDigit()
                                .fontWeight(row.band == "Total" ? .bold : .regular)
                        }
                        .width(min: 50, ideal: 60)

                        TableColumn("Mults") { row in
                            Text("\(row.mults)")
                                .monospacedDigit()
                                .fontWeight(row.band == "Total" ? .bold : .regular)
                        }
                        .width(min: 50, ideal: 60)
                    }
                    .alternatingRowBackgrounds()

                    Divider()

                    // Final score
                    HStack {
                        Text("Final Score:")
                            .font(.title3)
                        Spacer()
                        Text("\(contestManager.score.finalScore)")
                            .font(.title.monospacedDigit().bold())
                            .minimumScaleFactor(0.7)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Final score: \(contestManager.score.finalScore)")
                    .padding()
                    .background(.bar)
                }
                .frame(minWidth: 300, maxHeight: .infinity)

                // Right: Rate graph
                VStack(alignment: .leading) {
                    Text("QSO Rate")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)

                    if rateData.isEmpty {
                        ContentUnavailableView(
                            "No Data Yet",
                            systemImage: "chart.xyaxis.line",
                            description: Text("Rate graph will appear after logging QSOs")
                        )
                    } else {
                        RateGraphView(timeSeries: rateData)
                            .padding()
                    }
                }
                .frame(minWidth: 300, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: contestManager.score.totalQSOs) {
                rateData = await contestManager.rateTimeSeries()
            }
        } else {
            ContentUnavailableView(
                "No Active Contest",
                systemImage: "trophy",
                description: Text("Start a contest to see score summary")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Private

    @Environment(ContestManager.self) private var contestManager
    @State private var rateData: [(date: Date, count: Int)] = []

    private var bandBreakdown: [BandScoreRow] {
        let score = contestManager.score
        let bands = contestManager.definition?.bands ?? []

        var rows: [BandScoreRow] = bands.compactMap { band in
            let qsos = score.qsosByBand[band] ?? 0
            guard qsos > 0 else {
                return nil
            }
            return BandScoreRow(
                band: band,
                qsos: qsos,
                points: score.pointsByBand[band] ?? 0,
                mults: score.multsByBand[band] ?? 0
            )
        }

        // Total row
        rows.append(BandScoreRow(
            band: "Total",
            qsos: score.totalQSOs,
            points: score.totalPoints,
            mults: score.multiplierCount
        ))

        return rows
    }
}

// MARK: - BandScoreRow

struct BandScoreRow: Identifiable {
    let band: String
    let qsos: Int
    let points: Int
    let mults: Int

    var id: String {
        band
    }
}
