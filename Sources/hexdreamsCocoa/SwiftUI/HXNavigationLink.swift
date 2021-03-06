//
//  SEFeedNavigationLink.swift
//  SwiftExplorer
//
//  Created by Kenny Leung on 9/29/20.
//  Copyright © 2020 Kenny Leung. All rights reserved.
//

import SwiftUI

public struct HXNavigationLink<Label:View,Destination:View> : View {

    private let destination:Destination?
    private let label:()->Label

    public init(destination:Destination?, label:@escaping ()->Label) {
        self.destination = destination
        self.label = label
    }

    public var body: some View {
        if self.destination == nil {
            label()
        } else {
            NavigationLink(destination:self.destination!, label:label);
        }
    }
}

struct HXNavigationLink_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            List {
                HXNavigationLink(destination:nil as Text?) {
                    Text("No Destination")
                }
                HXNavigationLink(destination:Text("")) {
                    Text("Has Destination")
                }
            }
        }
    }
}
