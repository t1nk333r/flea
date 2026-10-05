// The fork's pure JavaScript suites, driven like tests/js/harness.qml (which the fork never edits).
import QtQuick

Item {
    Component.onCompleted: {
        var failures = [];
        var checked = 0;

        function check(label, actual, expected) {
            checked += 1;
            if (actual !== expected)
                failures.push(label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected));
        }

        // One [name, suite] row per suite, beside its import above.
        var suites = [
        ];
        for (var s = 0; s < suites.length; s++)
            suites[s][1].run(check, suites[s][0]);

        for (var i = 0; i < failures.length; i++)
            console.log("FAIL " + failures[i]);
        console.log(suites.length + " suites, " + checked + " checks, " + failures.length + " failed");
        Qt.exit(failures.length === 0 ? 0 : 1);
    }
}
