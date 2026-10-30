set -e
trap 'sendevent /dev/input/event1 3 47 0; sendevent /dev/input/event1 3 57 -1; sendevent /dev/input/event1 0 0 0; sendevent /dev/input/event1 3 47 1; sendevent /dev/input/event1 3 57 -1; sendevent /dev/input/event1 0 0 0' EXIT
sendevent /dev/input/event1 3 47 0
sendevent /dev/input/event1 3 57 1100
sendevent /dev/input/event1 3 55 0
sendevent /dev/input/event1 3 48 12
sendevent /dev/input/event1 3 49 12
sendevent /dev/input/event1 3 58 100
sendevent /dev/input/event1 3 53 13166
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sleep 0.04
sendevent /dev/input/event1 3 47 1
sendevent /dev/input/event1 3 57 1101
sendevent /dev/input/event1 3 55 0
sendevent /dev/input/event1 3 48 12
sendevent /dev/input/event1 3 49 12
sendevent /dev/input/event1 3 58 100
sendevent /dev/input/event1 3 53 19602
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sleep 0.05
sendevent /dev/input/event1 3 47 0
sendevent /dev/input/event1 3 53 12697
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sendevent /dev/input/event1 3 47 1
sendevent /dev/input/event1 3 53 20071
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sleep 0.025
sendevent /dev/input/event1 3 47 0
sendevent /dev/input/event1 3 53 12228
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sendevent /dev/input/event1 3 47 1
sendevent /dev/input/event1 3 53 20540
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sleep 0.025
sendevent /dev/input/event1 3 47 0
sendevent /dev/input/event1 3 53 11759
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sendevent /dev/input/event1 3 47 1
sendevent /dev/input/event1 3 53 21009
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sleep 0.025
sendevent /dev/input/event1 3 47 0
sendevent /dev/input/event1 3 53 11289
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sendevent /dev/input/event1 3 47 1
sendevent /dev/input/event1 3 53 21479
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sleep 0.025
sendevent /dev/input/event1 3 47 0
sendevent /dev/input/event1 3 53 10820
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sendevent /dev/input/event1 3 47 1
sendevent /dev/input/event1 3 53 21948
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sleep 0.025
sendevent /dev/input/event1 3 47 0
sendevent /dev/input/event1 3 53 10351
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sendevent /dev/input/event1 3 47 1
sendevent /dev/input/event1 3 53 22417
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sleep 0.025
sendevent /dev/input/event1 3 47 0
sendevent /dev/input/event1 3 53 9882
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sendevent /dev/input/event1 3 47 1
sendevent /dev/input/event1 3 53 22886
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sleep 0.025
sendevent /dev/input/event1 3 47 0
sendevent /dev/input/event1 3 53 9412
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sendevent /dev/input/event1 3 47 1
sendevent /dev/input/event1 3 53 23356
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sleep 0.025
sendevent /dev/input/event1 3 47 0
sendevent /dev/input/event1 3 53 8943
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sendevent /dev/input/event1 3 47 1
sendevent /dev/input/event1 3 53 23825
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sleep 0.025
sendevent /dev/input/event1 3 47 0
sendevent /dev/input/event1 3 53 8474
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sendevent /dev/input/event1 3 47 1
sendevent /dev/input/event1 3 53 24294
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sleep 0.025
sendevent /dev/input/event1 3 47 0
sendevent /dev/input/event1 3 53 8005
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sendevent /dev/input/event1 3 47 1
sendevent /dev/input/event1 3 53 24763
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sleep 0.025
sendevent /dev/input/event1 3 47 0
sendevent /dev/input/event1 3 53 7535
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sendevent /dev/input/event1 3 47 1
sendevent /dev/input/event1 3 53 25233
sendevent /dev/input/event1 3 54 14483
sendevent /dev/input/event1 0 0 0
sleep 0.025
sleep 0.12
sendevent /dev/input/event1 3 47 1
sendevent /dev/input/event1 3 57 -1
sendevent /dev/input/event1 0 0 0
sendevent /dev/input/event1 3 47 0
sendevent /dev/input/event1 3 57 -1
sendevent /dev/input/event1 0 0 0
