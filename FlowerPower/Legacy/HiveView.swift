//
//  HiveView.swift
//  FlowerPower
//
//  Created by Kyle Peterson on 11/14/23.
//

import SwiftUI

import SwiftUI

struct HiveView: View {
    @ObservedObject var hive: Hive

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<hive.cells.count, id: \.self) { index in
                        HexagonView(cell: hive.cells[index])
                            .frame(width: 100, height: 100) // Adjust size as needed
                            .foregroundColor(self.colorForCell(cell: hive.cells[index]))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func colorForCell(cell: HiveCell) -> Color {
        switch cell.contents {
        case .empty:
            return Color.white
        case .bee(let bee):
            return colorForBee(bee: bee)
        case .resource(let resourceType, _):
            return colorForResource(resourceType: resourceType)
        }
    }

    private func colorForBee(bee: Bee) -> Color {
        switch bee.type {
        case .queen:
            return Color.purple
        case .worker:
            return Color.blue
        case .drone:
            return Color.orange
        }
    }

    private func colorForResource(resourceType: ResourceType) -> Color {
        switch resourceType {
        case .nectar:
            return Color.yellow
        case .pollen:
            return Color.green
        case .water:
            return Color.blue
        case .propolis:
            return Color.gray
        case .wax:
            return Color.yellow
        case .royalJelly:
            return Color.orange
        }
    }
}

struct HexagonView: View {
    var cell: HiveCell

    var body: some View {
        PolygonShape(sides: 6)
            .stroke(Color.black, lineWidth: 2)
            .background(PolygonShape(sides: 6).fill(Color.white))
            .overlay(content)
            .aspectRatio(1, contentMode: .fit)
    }

    var content: some View {
        switch cell.contents {
        case .empty:
            return AnyView(EmptyView())
        case .bee(let bee):
            return AnyView(Text(bee.type.rawValue))
        case .resource(let resourceType, let quantity):
            return AnyView(Text("\(resourceType.rawValue): \(quantity)"))
        }
    }
}

struct PolygonShape: Shape {
    let sides: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let angle = CGFloat.pi * 2 / CGFloat(sides)

        for side in 0..<sides {
            let x = rect.midX + cos(CGFloat(side) * angle) * rect.width / 2
            let y = rect.midY + sin(CGFloat(side) * angle) * rect.height / 2
            if side == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        path.closeSubpath()
        return path
    }
}


#Preview {
    HiveView(hive: Hive(hiveLocation: .init(coordinates: (1,1), locationType: .animalBurrow)))
}
