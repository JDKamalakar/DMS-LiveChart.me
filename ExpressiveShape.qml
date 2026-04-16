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
    
    // Smoothly initialize position to prevent top-left jump
    Component.onCompleted: {
        updatePosition();
    }
    
    function updatePosition() {
        let pW = (parent && parent.width > 200) ? parent.width : 800;
        let pH = (parent && parent.height > 200) ? parent.height : 540;
        
        // Full width distribution to ensure they appear on both sides
        x = Math.random() * (pW - size);
        y = Math.random() * (pH - size);
        rotation = Math.random() * 360;
        
        // Activate animations once we have a sane position
        animX.running = true;
        animY.running = true;
    }

    Rectangle {
        id: shape
        anchors.fill: parent
        radius: size / 2
        opacity: 0.35
        
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.color1 }
            GradientStop { position: 1.0; color: root.color2 }
        }
        
        // Morphing effect (changing scale and radius smoothly)
        SequentialAnimation on scale {
            loops: Animation.Infinite
            NumberAnimation { from: 0.9; to: 1.25; duration: root.duration * 0.4; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.25; to: 0.9; duration: root.duration * 0.4; easing.type: Easing.InOutSine }
        }
        
        SequentialAnimation on radius {
            loops: Animation.Infinite
            NumberAnimation { from: size / 2.1; to: size / 3; duration: root.duration * 0.35; easing.type: Easing.InOutSine }
            NumberAnimation { from: size / 3; to: size / 2.1; duration: root.duration * 0.35; easing.type: Easing.InOutSine }
        }

        // Constant drifting rotation
        NumberAnimation on rotation {
            from: 0; to: 360
            duration: root.duration * 2
            loops: Animation.Infinite
        }
    }
    
    // Fluid Independent Drift
    NumberAnimation {
        id: animX
        target: root
        property: "x"
        running: false // Wait for initialization
        loops: Animation.Infinite
        duration: root.duration * (0.8 + Math.random() * 0.4)
        to: {
            let pW = (root.parent && root.parent.width > 0) ? root.parent.width : 800;
            return Math.random() * (pW - size);
        }
        easing.type: Easing.InOutSine
        onFinished: {
            let pW = (root.parent && root.parent.width > 0) ? root.parent.width : 800;
            to = Math.random() * (pW - size);
        }
    }

    NumberAnimation {
        id: animY
        target: root
        property: "y"
        running: false // Wait for initialization
        loops: Animation.Infinite
        duration: root.duration * (0.8 + Math.random() * 0.4)
        to: {
            let pH = (root.parent && root.parent.height > 0) ? root.parent.height : 540;
            return Math.random() * (pH - size);
        }
        easing.type: Easing.InOutSine
        onFinished: {
            let pH = (root.parent && root.parent.height > 0) ? root.parent.height : 540;
            to = Math.random() * (pH - size);
        }
    }
}
