RAM over Http for Sagittarius Scheme
=======

This is a utility library of RAM over Http.

Pre-condition
=======
This library uses


How to use
=======

For UC1

    (start-session 
     "http://{Root TSM wallet handler URL}"
     "IMSI-{your SIM's IMSI}"
     :trace #t)

For UC0 (Blackberry specific use case)

    (start-session 
     "http://{Root TSM wallet handler URL}"
     "IMSI-{your SIM's IMSI}"
     :trace #t
     :headers '(:x-bbwallet-msisdn "{MSISDN}" :x-bbwallet-model "BlackBerry"
                :x-bbwallet-carrier "{NMO name}"
                :x-bbwallet-seid "{Secure Element ID}"
                :x-bbwallet-imsi "{your SIM's IMSI}"
                :x-bbwallet-new-device "true"))

