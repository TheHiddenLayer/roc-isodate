## The Time module provides the `Time` type as well as functions for working with time values.
##
## These functions include functions for creating `Time` objects from various numeric values, converting `Time`s to and from ISO 8601 strings, and performing arithmetic operations on `Time`s.
module [
    addDurationAndTime,
    addHours,
    addMinutes,
    addNanoseconds,
    addSeconds,
    addTimeAndDuration,
    fromHms,
    fromHmsn,
    fromIsoStr,
    fromIsoU8,
    fromNanosSinceMidnight,
    midnight,
    normalize,
    Time,
    toIsoStr,
    toIsoU8,
    toNanosSinceMidnight,
]

import Const
import Const exposing [
    nanosPerHour,
    nanosPerMinute,
    nanosPerSecond,
]
import Duration
import Duration exposing [Duration]
import Utils exposing [
    expandIntWithZeros,
    splitListAtIndices,
    splitUtf8AndKeepDelimiters,
    utf8ToFrac,
    utf8ToIntSigned,
    validateUtf8SingleBytes,
]
import Unsafe exposing [unwrap] # for unit testing only

## ```
## Time : { 
##     hour : I8, 
##     minute : U8, 
##     second : U8, 
##     nanosecond : U32 
## }
## ```
Time : { hour : I8, minute : U8, second : U8, nanosecond : U32 }

## `Time` object representing 00:00:00.
midnight : Time
midnight = { hour: 0, minute: 0, second: 0, nanosecond: 0 }

normalize : Time -> Time
normalize = \time ->
    hNormalized = time.hour |> Num.rem Const.hoursPerDay |> Num.add Const.hoursPerDay |> Num.rem Const.hoursPerDay
    fromHmsn hNormalized time.minute time.second time.nanosecond

expect Time.normalize (fromHms -1 0 0) == fromHms 23 0 0
expect Time.normalize (fromHms 24 0 0) == fromHms 0 0 0
expect Time.normalize (fromHms 25 0 0) == fromHms 1 0 0

## Create a `Time` object from the hour, minute, and second.
fromHms : Int *, Int *, Int * -> Time
fromHms = \hour, minute, second -> { hour: Num.toI8 hour, minute: Num.toU8 minute, second: Num.toU8 second, nanosecond: 0u32 }

## Create a `Time` object from the hour, minute, second, and nanosecond.
fromHmsn : Int *, Int *, Int *, Int * -> Time
fromHmsn = \hour, minute, second, nanosecond ->
    { hour: Num.toI8 hour, minute: Num.toU8 minute, second: Num.toU8 second, nanosecond: Num.toU32 nanosecond }

## Convert nanoseconds since midnight to a `Time` object.
toNanosSinceMidnight : Time -> I64
toNanosSinceMidnight = \time ->
    hNanos = time.hour |> Num.toI64 |> Num.mul Const.nanosPerHour |> Num.toI64
    mNanos = time.minute |> Num.toI64 |> Num.mul Const.nanosPerMinute |> Num.toI64
    sNanos = time.second |> Num.toI64 |> Num.mul Const.nanosPerSecond |> Num.toI64
    nanos = time.nanosecond |> Num.toI64
    hNanos + mNanos + sNanos + nanos

## Convert a `Time` object to the number of nanoseconds since midnight.
fromNanosSinceMidnight : Int * -> Time
fromNanosSinceMidnight = \nanos ->
    nanos1 = nanos |> Num.rem Const.nanosPerDay |> Num.add Const.nanosPerDay |> Num.rem Const.nanosPerDay |> Num.toU64
    nanos2 = nanos1 % nanosPerHour
    minute = nanos2 // nanosPerMinute |> Num.toU8
    nanos3 = nanos2 % nanosPerMinute
    second = nanos3 // nanosPerSecond |> Num.toU8
    nanosecond = nanos3 % nanosPerSecond |> Num.toU32
    hour = (nanos - Num.intCast (Num.toI64 minute * nanosPerMinute + Num.toI64 second * nanosPerSecond + Num.toI64 nanosecond)) // nanosPerHour |> Num.toI8 # % Const.hoursPerDay |> Num.toI8
    { hour, minute, second, nanosecond }

## Add nanoseconds to a `Time` object.
addNanoseconds : Time, Int * -> Time
addNanoseconds = \time, nanos ->
    toNanosSinceMidnight time + Num.toI64 nanos |> fromNanosSinceMidnight

## Add seconds to a `Time` object.
addSeconds : Time, Int * -> Time
addSeconds = \time, seconds -> addNanoseconds time (seconds * Const.nanosPerSecond)

## Add minutes to a `Time` object.
addMinutes : Time, Int * -> Time
addMinutes = \time, minutes -> addNanoseconds time (minutes * Const.nanosPerMinute)

## Add hours to a `Time` object.
addHours : Time, Int * -> Time
addHours = \time, hours -> addNanoseconds time (hours * Const.nanosPerHour)

## Add a `Duration` object to a `Time` object.
addDurationAndTime : Duration, Time -> Time
addDurationAndTime = \duration, time ->
    durationNanos = Duration.toNanoseconds duration
    timeNanos = toNanosSinceMidnight time |> Num.toI128
    (durationNanos + timeNanos) |> fromNanosSinceMidnight

## Add a `Time` object to a `Duration` object.
addTimeAndDuration : Time, Duration -> Time
addTimeAndDuration = \time, duration -> addDurationAndTime duration time

stripTandZ : List U8 -> List U8
stripTandZ = \bytes ->
    when bytes is
        ['T', .. as tail] -> stripTandZ tail
        [.. as head, 'Z'] -> head
        _ -> bytes

## Convert a `Time` object to an ISO 8601 string.
toIsoStr : Time -> Str
toIsoStr = \time ->
    expandIntWithZeros time.hour 2
    |> Str.concat ":"
    |> Str.concat (expandIntWithZeros time.minute 2)
    |> Str.concat ":"
    |> Str.concat (expandIntWithZeros time.second 2)
    |> Str.concat (nanosToFracStr time.nanosecond)

nanosToFracStr : U32 -> Str
nanosToFracStr = \nanos ->
    length = countFracWidth nanos 9
    untrimmedStr = (if nanos == 0 then "" else Str.concat "," (expandIntWithZeros nanos length))
    when untrimmedStr |> Str.toUtf8 |> List.takeFirst (length + 1) |> Str.fromUtf8 is
        Ok str -> str
        Err _ -> untrimmedStr

countFracWidth : U32, Int _ -> Int _
countFracWidth = \num, width ->
    if num == 0 then
        0
    else if num % 10 == 0 then
        countFracWidth (num // 10) (width - 1)
    else
        width

## Convert a `Time` object to an ISO 8601 list of UTF-8 bytes.
toIsoU8 : Time -> List U8
toIsoU8 = \time -> toIsoStr time |> Str.toUtf8

## Convert an ISO 8601 string to a `Time` object.
fromIsoStr : Str -> Result Time [InvalidTimeFormat]
fromIsoStr = \str -> Str.toUtf8 str |> fromIsoU8

## Convert an ISO 8601 list of UTF-8 bytes to a `Time` object.
fromIsoU8 : List U8 -> Result Time [InvalidTimeFormat]
fromIsoU8 = \bytes ->
    if validateUtf8SingleBytes bytes then
        strippedBytes = stripTandZ bytes
        when (splitUtf8AndKeepDelimiters strippedBytes ['.', ',', '+', '-'], List.last bytes) is
            # time.fractionaltime+timeoffset / time,fractionaltime-timeoffset
            ([timeBytes, [byte1], fractionalBytes, [byte2], offsetBytes], Ok lastByte) if lastByte != 'Z' ->
                timeRes = parseFractionalTime timeBytes (List.join [[byte1], fractionalBytes])
                offsetRes = parseTimeOffset (List.join [[byte2], offsetBytes])
                combineTimeAndOffsetResults timeRes offsetRes

            # time+timeoffset / time-timeoffset
            ([timeBytes, [byte1], offsetBytes], Ok lastByte) if (byte1 == '+' || byte1 == '-') && lastByte != 'Z' ->
                timeRes = parseWholeTime timeBytes
                offsetRes = parseTimeOffset (List.join [[byte1], offsetBytes])
                combineTimeAndOffsetResults timeRes offsetRes

            # time.fractionaltime / time,fractionaltime
            ([timeBytes, [byte1], fractionalBytes], _) if byte1 == ',' || byte1 == '.' ->
                parseFractionalTime timeBytes (List.join [[byte1], fractionalBytes])

            # time
            ([timeBytes], _) -> parseWholeTime timeBytes
            _ -> Err InvalidTimeFormat
    else
        Err InvalidTimeFormat

combineTimeAndOffsetResults = \timeRes, offsetRes ->
    when (timeRes, offsetRes) is
        (Ok time, Ok offset) ->
            Time.addTimeAndDuration time offset |> Ok

        (_, _) -> Err InvalidTimeFormat

parseWholeTime : List U8 -> Result Time [InvalidTimeFormat]
parseWholeTime = \bytes ->
    when bytes is
        [_, _] -> parseLocalTimeHour bytes # hh
        [_, _, _, _] -> parseLocalTimeMinuteBasic bytes # hhmm
        [_, _, ':', _, _] -> parseLocalTimeMinuteExtended bytes # hh:mm
        [_, _, _, _, _, _] -> parseLocalTimeBasic bytes # hhmmss
        [_, _, ':', _, _, ':', _, _] -> parseLocalTimeExtended bytes # hh:mm:ss
        _ -> Err InvalidTimeFormat

parseFractionalTime : List U8, List U8 -> Result Time [InvalidTimeFormat]
parseFractionalTime = \wholeBytes, fractionalBytes ->
    combineDurationResAndTime = \durationRes, time ->
        when durationRes is
            Ok duration -> Time.addTimeAndDuration time duration |> Ok
            Err _ -> Err InvalidTimeFormat
    when (wholeBytes, utf8ToFrac fractionalBytes) is
        ([_, _], Ok frac) -> # hh
            time = parseLocalTimeHour? wholeBytes
            frac * Const.nanosPerHour |> Num.round |> Duration.fromNanoseconds |> combineDurationResAndTime time

        ([_, _, _, _], Ok frac) -> # hhmm
            time = parseLocalTimeMinuteBasic? wholeBytes
            frac * Const.nanosPerMinute |> Num.round |> Duration.fromNanoseconds |> combineDurationResAndTime time

        ([_, _, ':', _, _], Ok frac) -> # hh:mm
            time = parseLocalTimeMinuteExtended? wholeBytes
            frac * Const.nanosPerMinute |> Num.round |> Duration.fromNanoseconds |> combineDurationResAndTime time

        ([_, _, _, _, _, _], Ok frac) -> # hhmmss
            time = parseLocalTimeBasic? wholeBytes
            frac * Const.nanosPerSecond |> Num.round |> Duration.fromNanoseconds |> combineDurationResAndTime time

        ([_, _, ':', _, _, ':', _, _], Ok frac) -> # hh:mm:ss
            time = parseLocalTimeExtended? wholeBytes
            frac * Const.nanosPerSecond |> Num.round |> Duration.fromNanoseconds |> combineDurationResAndTime time

        _ -> Err InvalidTimeFormat

parseTimeOffset : List U8 -> Result Duration [InvalidTimeFormat]
parseTimeOffset = \bytes ->
    when bytes is
        ['-', h1, h2] ->
            parseTimeOffsetHelp h1 h2 '0' '0' 1

        ['+', h1, h2] ->
            parseTimeOffsetHelp h1 h2 '0' '0' -1

        ['-', h1, h2, m1, m2] ->
            parseTimeOffsetHelp h1 h2 m1 m2 1

        ['+', h1, h2, m1, m2] ->
            parseTimeOffsetHelp h1 h2 m1 m2 -1

        ['-', h1, h2, ':', m1, m2] ->
            parseTimeOffsetHelp h1 h2 m1 m2 1

        ['+', h1, h2, ':', m1, m2] ->
            parseTimeOffsetHelp h1 h2 m1 m2 -1

        _ -> Err InvalidTimeFormat

parseTimeOffsetHelp : U8, U8, U8, U8, I64 -> Result Duration [InvalidTimeFormat]
parseTimeOffsetHelp = \h1, h2, m1, m2, sign ->
    isValidOffset = \offset -> if offset >= -14 * Const.nanosPerHour && offset <= 12 * Const.nanosPerHour then Valid else Invalid
    when (utf8ToIntSigned [h1, h2], utf8ToIntSigned [m1, m2]) is
        (Ok hour, Ok minute) ->
            offsetNanos = sign * (hour * Const.nanosPerHour + minute * Const.nanosPerMinute)
            when isValidOffset offsetNanos is
                Valid -> Duration.fromNanoseconds offsetNanos |> Result.mapErr \_ -> InvalidTimeFormat
                Invalid -> Err InvalidTimeFormat

        (_, _) -> Err InvalidTimeFormat

parseLocalTimeHour : List U8 -> Result Time [InvalidTimeFormat]
parseLocalTimeHour = \bytes ->
    when utf8ToIntSigned bytes is
        Ok hour if hour >= 0 && hour <= 24 ->
            Time.fromHms hour 0 0 |> Ok

        Ok _ -> Err InvalidTimeFormat
        Err _ -> Err InvalidTimeFormat

parseLocalTimeMinuteBasic : List U8 -> Result Time [InvalidTimeFormat]
parseLocalTimeMinuteBasic = \bytes ->
    when splitListAtIndices bytes [2] is
        [hourBytes, minuteBytes] ->
            when (utf8ToIntSigned hourBytes, utf8ToIntSigned minuteBytes) is
                (Ok hour, Ok minute) if hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 ->
                    Time.fromHms hour minute 0 |> Ok

                (Ok 24, Ok 0) ->
                    Time.fromHms 24 0 0 |> Ok

                (_, _) -> Err InvalidTimeFormat

        _ -> Err InvalidTimeFormat

parseLocalTimeMinuteExtended : List U8 -> Result Time [InvalidTimeFormat]
parseLocalTimeMinuteExtended = \bytes ->
    when splitListAtIndices bytes [2, 3] is
        [hourBytes, _, minuteBytes] ->
            when (utf8ToIntSigned hourBytes, utf8ToIntSigned minuteBytes) is
                (Ok hour, Ok minute) if hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 ->
                    Time.fromHms hour minute 0 |> Ok

                (Ok 24, Ok 0) ->
                    Time.fromHms 24 0 0 |> Ok

                (_, _) -> Err InvalidTimeFormat

        _ -> Err InvalidTimeFormat

parseLocalTimeBasic : List U8 -> Result Time [InvalidTimeFormat]
parseLocalTimeBasic = \bytes ->
    when splitListAtIndices bytes [2, 4] is
        [hourBytes, minuteBytes, secondBytes] ->
            when (utf8ToIntSigned hourBytes, utf8ToIntSigned minuteBytes, utf8ToIntSigned secondBytes) is
                (Ok h, Ok m, Ok s) if h >= 0 && h <= 23 && m >= 0 && m <= 59 && s >= 0 && s <= 59 ->
                    Time.fromHms h m s |> Ok

                (Ok 24, Ok 0, Ok 0) ->
                    Time.fromHms 24 0 0 |> Ok

                (_, _, _) -> Err InvalidTimeFormat

        _ -> Err InvalidTimeFormat

parseLocalTimeExtended : List U8 -> Result Time [InvalidTimeFormat]
parseLocalTimeExtended = \bytes ->
    when splitListAtIndices bytes [2, 3, 5, 6] is
        [hourBytes, _, minuteBytes, _, secondBytes] ->
            when (utf8ToIntSigned hourBytes, utf8ToIntSigned minuteBytes, utf8ToIntSigned secondBytes) is
                (Ok h, Ok m, Ok s) if h >= 0 && h <= 23 && m >= 0 && m <= 59 && s >= 0 && s <= 59 ->
                    Time.fromHms h m s |> Ok

                (Ok 24, Ok 0, Ok 0) ->
                    Time.fromHms 24 0 0 |> Ok

                (_, _, _) -> Err InvalidTimeFormat

        _ -> Err InvalidTimeFormat

# <===== TESTS ====>
# <---- addNanoseconds ---->
expect addNanoseconds (fromHmsn 12 34 56 5) Const.nanosPerSecond == fromHmsn 12 34 57 5
expect addNanoseconds (fromHmsn 12 34 56 5) -Const.nanosPerSecond == fromHmsn 12 34 55 5

# <---- addSeconds ---->
expect addSeconds (fromHms 12 34 56) 59 == fromHms 12 35 55
expect addSeconds (fromHms 12 34 56) -59 == fromHms 12 33 57

# <---- addMinutes ---->
expect addMinutes (fromHms 12 34 56) 59 == fromHms 13 33 56
expect addMinutes (fromHms 12 34 56) -59 == fromHms 11 35 56

# <---- addHours ---->
expect addHours (fromHms 12 34 56) 1 == fromHms 13 34 56
expect addHours (fromHms 12 34 56) -1 == fromHms 11 34 56
expect addHours (fromHms 12 34 56) 12 == fromHms 24 34 56

# <---- addTimeAndDuration ---->
expect
    addTimeAndDuration (fromHms 0 0 0) (Duration.fromHours 1 |> unwrap "will not overflow") == fromHms 1 0 0

# <---- fromNanosSinceMidnight ---->
expect fromNanosSinceMidnight -123 == fromHmsn -1 59 59 999_999_877
expect fromNanosSinceMidnight 0 == midnight
expect fromNanosSinceMidnight (24 * Const.nanosPerHour) == fromHms 24 0 0
expect fromNanosSinceMidnight (25 * nanosPerHour) == fromHms 25 0 0
expect fromNanosSinceMidnight (12 * nanosPerHour + 34 * nanosPerMinute + 56 * nanosPerSecond + 5) == fromHmsn 12 34 56 5

# <---- toIsoStr ---->
expect toIsoStr (fromHmsn 12 34 56 5) == "12:34:56,000000005"
expect toIsoStr midnight == "00:00:00"
expect
    str = toIsoStr (fromHmsn 0 0 0 500_000_000)
    str == "00:00:00,5"

# <---- fromNanosSinceMidnight ---->
expect fromNanosSinceMidnight -123 == fromHmsn -1 59 59 999_999_877
expect fromNanosSinceMidnight 0 == midnight
expect fromNanosSinceMidnight (24 * Const.nanosPerHour) == fromHms 24 0 0
expect fromNanosSinceMidnight (25 * Const.nanosPerHour) == fromHms 25 0 0

# <---- toNanosSinceMidnight ---->
expect toNanosSinceMidnight { hour: 12, minute: 34, second: 56, nanosecond: 5 } == 12 * nanosPerHour + 34 * nanosPerMinute + 56 * nanosPerSecond + 5
expect toNanosSinceMidnight (fromHmsn 12 34 56 5) == 12 * Const.nanosPerHour + 34 * Const.nanosPerMinute + 56 * Const.nanosPerSecond + 5
expect toNanosSinceMidnight (fromHmsn -1 0 0 0) == -1 * Const.nanosPerHour
