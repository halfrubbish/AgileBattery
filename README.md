This module is a work in progress and does not contain complete code. I am currently writing it and will remove this message when in a usable state. 



# AgileBattery
Powershell module to allow Tesla Powerwall and Octopus Energy integration for those on an Agile tariff. The module will continously control of the amount of energy stored in the powerwall, charging it during the cheapest periods of the day 

# Setup
You'll need to generate a Tesla refresh access token using the page here: https://tesla-info.com/tesla-token.php

You'll need to set your powerwall to Time Based Control, and create a schedule with 1 single half hour "off-peak" tariff slot. I would recommend picking a slot in the early hours of the morning as it will charge every day in that slot they tend to be cheaper in general then. This is required as otherwise varying the charge/discharge ratio (Backup vs Time Based Control %) will not work.  


# Referral
Use my referral link to buy a Tesla and get up to £500 off. https://ts.la/matt33479
