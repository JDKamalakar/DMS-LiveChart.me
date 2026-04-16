import QtQuick
import qs.Common

Item {
    id: root
    
    property color color1: Theme.primary
    property color color2: Theme.secondary
    property real size: 200
    property int duration: 15000
    
    width: size
    height: size
    
    Rectangle {
        id: shape
        anchors.fill: parent
        radius: size / 2
        opacity: 0.2
        
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.color1 }
            GradientStop { position: 1.0; color: root.color2 }
        }
        
        // Morphing effect (changing scale and radius slightly)
        SequentialAnimation on scale {
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 1.15; duration: root.duration / 2; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.15; to: 1.0; duration: root.duration / 2; easing.type: Easing.InOutSine }
        }
        
        SequentialAnimation on radius {
            loops: Animation.Infinite
            NumberAnimation { from: size / 2; to: size / 2.5; duration: root.duration / 3; easing.type: Easing.InOutSine }
            NumberAnimation { from: size / 2.5; to: size / 2; duration: root.duration / 3; easing.type: Easing.InOutSine }
        }
    }
    
    // Random movement within parent
    SequentialAnimation {
        running: true
        loops: Animation.Infinite
        
        property real targetX: Math.random() * (parent.width - size)
        property real targetY: Math.random() * (parent.height - size)
        
        NumberAnimation {
            target: root
            property: "x"
            to: (Math.random() * 0.8 + 0.1) * (root.parent ? root.parent.width : 500) - size/2
            duration: root.duration
            easing.type: Easing.InOutCubic
        }
        
        NumberAnimation {
            target: root
            property: "y"
            to: (Math.random() * 0.8 + 0.1) * (root.parent ? root.parent.height : 500) - size/2
            duration: root.duration
            easing.type: Easing.InOutCubic
        }
    }
}
