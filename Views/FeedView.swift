import SwiftUI

struct FeedView: View {
  @ObservedObject var favoritesManager = FavoritesManager.shared
  @Binding var appearance: AppearanceSettings
  @Binding var persistedIndex: Int
  @State private var currentPosition: Int = 0
  @State private var dragOffset: CGFloat = 0
  @State private var isDragging: Bool = false

  private let quotes = LocalQuotes.quotes
  private let screenHeight = UIScreen.main.bounds.height
  private let maxDailyQuotes = 5

  var body: some View {
    let order = todayOrder
    let orderCount = order.count
    let currentQuoteIndex = quoteIndex(at: currentPosition, in: order) ?? 0
    let prevPos = currentPosition > 0 ? currentPosition - 1 : nil
    let nextPos = currentPosition + 1 < orderCount ? currentPosition + 1 : nil

    let upDragAmount = max(0, -dragOffset)
    let downDragAmount = max(0, dragOffset)
    let upProgress = min(1, upDragAmount / screenHeight)
    let downProgress = min(1, downDragAmount / screenHeight)

    ZStack {
      // Background
      Color.black.ignoresSafeArea(.all)

      // Quote cards stack
      ZStack {
        if let prevPos, let prevIndex = quoteIndex(at: prevPos, in: order) {
          quoteCard(at: prevIndex, isFirstOfDay: false, offset: -screenHeight + upDragAmount)
            .opacity(isDragging && dragOffset < 0 ? max(0, upProgress) : 0)
            .zIndex(0)
        }

        // Current card
        quoteCard(at: currentQuoteIndex, isFirstOfDay: currentPosition == 0, offset: dragOffset)
          .zIndex(1)

        // Next card (always show for infinite loop)
        if let nextPos, let nextIndex = quoteIndex(at: nextPos, in: order) {
          quoteCard(at: nextIndex, isFirstOfDay: false, offset: screenHeight - downDragAmount)
            .opacity(isDragging && dragOffset > 0 ? max(0, downProgress) : 0)
            .zIndex(0)
        }
      }
      .gesture(
        DragGesture(minimumDistance: 20)
          .onChanged { value in
            // Only respond to vertical drags (not horizontal)
            if abs(value.translation.height) > abs(value.translation.width) {
              if !isDragging {
                isDragging = true
                HapticManager.light()
              }

              dragOffset = value.translation.height
            }
          }
          .onEnded { value in
            let dragThreshold: CGFloat = screenHeight * 0.25
            let isFirst = currentPosition == 0
            if value.translation.height < -dragThreshold
              || value.predictedEndTranslation.height < -dragThreshold
            {
              // Swipe up → go forward (cap at end)
              if currentPosition + 1 < orderCount {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                  currentPosition += 1
                  dragOffset = 0
                }
                HapticManager.medium()
              } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                  dragOffset = 0
                }
                HapticManager.light()
              }
            } else if value.translation.height > dragThreshold
              || value.predictedEndTranslation.height > dragThreshold
            {
              // Swipe down → go backward (block on first)
              if currentPosition > 0 {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                  currentPosition -= 1
                  dragOffset = 0
                }
                HapticManager.medium()
              } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                  dragOffset = 0
                }
                HapticManager.light()
              }
            } else {
              // Spring back
              withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                dragOffset = 0
              }
            }

            isDragging = false
          }
      )
    }
    .ignoresSafeArea(.all)
    .onAppear {
      currentPosition = 0
      persistedIndex = 0
    }
    .onChange(of: persistedIndex) { newValue in
      currentPosition = min(newValue, todayOrder.count - 1)
    }
    .onChange(of: currentPosition) { newValue in
      persistedIndex = newValue
    }
    .onChange(of: todaySeedIndex) { _ in
      currentPosition = 0
      persistedIndex = 0
    }
  }

  @ViewBuilder
  private func quoteCard(at index: Int, isFirstOfDay: Bool, offset: CGFloat) -> some View {
    // Handle negative indices for infinite loop and ensure array is not empty
    if quotes.isEmpty {
      return AnyView(EmptyView())
    } else {
      let actualIndex = ((index % quotes.count) + quotes.count) % quotes.count
      let quote = quotes[actualIndex]
      let todayIndex = DailyQuoteSync.todayIndex()

      return AnyView(
        QuoteSlideView(
          quote: quote,
          index: actualIndex,
          isToday: isFirstOfDay,
          onToggleFavorite: {
            favoritesManager.toggleFavorite(quote)
          },
          appearance: $appearance
        )
        .offset(y: offset)
        .scaleEffect(1.0 - abs(offset) / (screenHeight * 2))
        .opacity(1.0 - abs(offset) / (screenHeight * 1.5))
      )
    }
  }

  private var todayOrder: [Int] {
    guard !quotes.isEmpty else { return [] }
    let today = todaySeedIndex
    var others = Array(0..<quotes.count).filter { $0 != today }
    var generator = SeededGenerator(
      seed: UInt64(DailyShuffle.seedValue(seed: today, total: quotes.count)))
    others.shuffle(using: &generator)
    let cappedOthers = Array(others.prefix(max(0, maxDailyQuotes - 1)))
    return [today] + cappedOthers
  }

  private var todaySeedIndex: Int {
    DailyQuoteSync.todayIndex()
  }

  private func quoteIndex(at position: Int, in order: [Int]) -> Int? {
    guard position >= 0, position < order.count else { return nil }
    return order[position]
  }
}

// MARK: - Deterministic daily shuffle (cap 5/day)
private enum DailyShuffle {
  static func order(total: Int, limit: Int, seed: Int) -> [Int] {
    guard total > 0 else { return [] }
    let cappedLimit = max(1, min(limit, total))
    var indices = Array(0..<total)
    var generator = SeededGenerator(seed: UInt64(seedValue(seed: seed, total: total)))
    indices.shuffle(using: &generator)
    return Array(indices.prefix(cappedLimit))
  }

  static func seedValue(seed: Int, total: Int) -> UInt64 {
    let a = UInt64(seed & 0xFFFF)
    let b = UInt64(total & 0xFFFF)
    return (a << 32) ^ (b << 16) ^ 0x9E37_79B9_7F4A_7C15
  }
}

private struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64
  init(seed: UInt64) {
    self.state = seed != 0 ? seed : 0x123_4567_89AB_CDEF
  }
  mutating func next() -> UInt64 {
    state ^= state << 7
    state ^= state >> 9
    state ^= 0xA076_1D64_78BD_642F
    return state
  }
}
