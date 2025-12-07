import SwiftUI

struct FeedView: View {
  @ObservedObject var favoritesManager = FavoritesManager.shared
  @Binding var appearance: AppearanceSettings
  @Binding var persistedIndex: Int
  @State private var currentIndex: Int = 0
  @State private var dragOffset: CGFloat = 0
  @State private var isDragging: Bool = false

  private let quotes = LocalQuotes.quotes
  private let screenHeight = UIScreen.main.bounds.height

  var body: some View {
    let upDragAmount = max(0, -dragOffset)
    let downDragAmount = max(0, dragOffset)
    let upProgress = min(1, upDragAmount / screenHeight)
    let downProgress = min(1, downDragAmount / screenHeight)

    ZStack {
      // Background
      Color.black.ignoresSafeArea(.all)

      // Quote cards stack
      ZStack {
        // Previous card (always show for infinite loop)
        quoteCard(at: currentIndex - 1, offset: -screenHeight + upDragAmount)
          .opacity(isDragging && dragOffset < 0 ? max(0, upProgress) : 0)
          .zIndex(0)

        // Current card
        quoteCard(at: currentIndex, offset: dragOffset)
          .zIndex(1)

        // Next card (always show for infinite loop)
        quoteCard(at: currentIndex + 1, offset: screenHeight - downDragAmount)
          .opacity(isDragging && dragOffset > 0 ? max(0, downProgress) : 0)
          .zIndex(0)
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
          let isToday = currentIndex == DailyQuoteSync.todayIndex()

          if value.translation.height < -dragThreshold
            || value.predictedEndTranslation.height < -dragThreshold
          {
            // Swipe up - go to previous quote (allowed even on today's quote)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
              currentIndex = (currentIndex - 1 + quotes.count) % quotes.count
              dragOffset = 0
            }
            HapticManager.medium()
          } else if value.translation.height > dragThreshold
            || value.predictedEndTranslation.height > dragThreshold
          {
            // Swipe down - go to next quote (block if on today's quote)
            if isToday {
              withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                dragOffset = 0
              }
              HapticManager.light()
            } else {
              withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentIndex = (currentIndex + 1) % quotes.count
                dragOffset = 0
              }
              HapticManager.medium()
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
      currentIndex = persistedIndex
    }
    .onChange(of: persistedIndex) { newValue in
      currentIndex = newValue
    }
    .onChange(of: currentIndex) { newValue in
      persistedIndex = newValue
    }
  }

  @ViewBuilder
  private func quoteCard(at index: Int, offset: CGFloat) -> some View {
    // Handle negative indices for infinite loop and ensure array is not empty
    if quotes.isEmpty {
      EmptyView()
    } else {
      let actualIndex = ((index % quotes.count) + quotes.count) % quotes.count
      let quote = quotes[actualIndex]
      let todayIndex = DailyQuoteSync.todayIndex()

      QuoteSlideView(
        quote: quote,
        index: actualIndex,
        isToday: actualIndex == todayIndex,
        onToggleFavorite: {
          favoritesManager.toggleFavorite(quote)
        },
        appearance: $appearance
      )
      .offset(y: offset)
      .scaleEffect(1.0 - abs(offset) / (screenHeight * 2))
      .opacity(1.0 - abs(offset) / (screenHeight * 1.5))
    }
  }
}
