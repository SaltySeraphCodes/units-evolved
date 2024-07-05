# This script updates data hopefully in real time
import os, json, sys, time

dir_path = os.path.dirname(os.path.realpath(__file__))
Local_Scripts = os.path.join(dir_path, "Scripts")
json_data = os.path.join(dir_path, "JsonData")
sim_outputPath =  os.path.join(json_data, "SimOutput")
dataBase = os.path.join(Local_Scripts, "StreamReaderData")

SETTINGS = {
    'showChats': True,
    'allFree': True, # make everything freee
    'sponsorFree': True, # channel Members get free commands
    'fixedCost': 0, # if >0 and allFree == false, all commands will cost this price
    'interval': 1, # rate in which to check for new commands, BROKEN until fixed...
    'prefix': ['!','/','$','%'],
    'filename': os.path.join(dataBase, 'streamchat.json'),
    'videoID': "FFZWwK1y3fI", #<-- Update this to your stream ID  (Testing stage: FFZWwK1y3fI) (production?:YWKbVdsyWXc)
    'commands': { # list of commands and parameters, their prices are the values
        'spawn': { # spawns in unit and binds chat member to it -- stuck there until it dies
            'totebot': 0,
            'woc': 0,
            'worm': 0,
            'haybot': 0,
            'tapebot': 0,
            'redtapebot': 0,
            'farmbot': 0,
        },
       'goto':{ # reads next input and follows player/unit defined
            'nn,n': 0 #shortcut to just follow seraph
        },
        'follow':{ # reads next input and follows player/unit defined
            'seraph': 0 #shortcut to just follow seraph
        },
        'attack': { # attempts to attack specified player/unit 
            'seraph': 0 #shortcut
        },
        'flee': { # attempts to run away from specified player/unit 
            'seraph': 0 #shortcut
        },
        'wander': 0, # wanders around aimless
        'stop': 0, # stops unit
        'explode': 0, # explodes unit
        'logout': 0, #saves and removes unit
        'login': 0 # spawns  user in as saved data or default
    },
    'single': ['wander', 'stop','explode','logout','login'] # list of all single param commands for extra validation
}

def outputData(data):
    print("outputing",data)
    with open(SETTINGS['filename'], 'w') as outfile:
        jsonData = json.dumps(data)
        outfile.write(jsonData)

def main():
    counter = 0
    counterMax = 10000
    while counter < counterMax:
        counter = counter + 1
        data = {'count': counter}
        outputData(data)
        time.sleep(0.025) # 40 times per second (should be synced?)

main()