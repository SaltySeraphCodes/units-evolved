from ast import parse
from socket import timeout
import pytchat # most recent thing in the core is the updated stuff
import time
import json
import os
import sys
import copy
#import requests
from winreg import *
#import vdf
import json
from shutil import copyfile
import shutil
# import smObjects


#FAKE PAYLOADS
superChatPayload = {'id': 122, 'command':"/kill", 'author': "saltyseraph", 'sponsor': True, 'userid': "kjdkjij90u0d", 'amount': 12.0}
regular_payload = {'id': 0, 'command': 'Hi', 'author': 'Lv Apples', 'sponsor': False, 'userid': 'UCSdVROtEFJMjUO_4f_aqPTg', 'amount': 0.0}
super2chat = {'id': 0, 'command': 'sup bryh', 'author': 'Blackoutdrunk', 'sponsor': False, 'userid': 'UCyTAzuTRkpJaPSYdLz95u1A', 'amount': 2.0}
GAME_ID = '387990'

chat = None

debug = False

###########################################################

# dir_path is the current directory
dir_path = os.path.dirname(os.path.realpath(__file__))

# commonly use sm folder locations
Local_Scripts = os.path.join(dir_path, "Scripts")
json_data = os.path.join(dir_path, "JsonData")
sim_outputPath =  os.path.join(json_data, "SimOutput")
#smBase = os.path.join(SM_Location, "Survival", "Scripts", "game") #Hard coding to just these scripts
dataBase = os.path.join(Local_Scripts, "StreamReaderData")
blueprintBase = os.path.join(dataBase, "blueprints") #location for stored databases
download_path = os.path.join(dir_path,"steamcmd","steamapps","workshop","content",GAME_ID)
steamcmd_path = os.path.join(dir_path,"steamcmd")

# commly used file locations
statOutput = os.path.join(dir_path, "DeathCounter.txt")
chatterData = os.path.join(dataBase, "chatterData.json")
simulationSettings = os.path.join(dataBase, "simulationSettings.json")
simulationData = os.path.join(sim_outputPath, "simulationOutput.json")

# Import settings? for now have global settings
# TODO: Money pool to allow viewers to donate to a common goal
# TODO: Natural Disasters
# TODO: Rename spawn to login and make one param (loads user or spawns default woc)
# TODO: Feed and grow gamemode: start as worm, eat to grow into farmbot?
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

def translateCoordinates(params):
    print('params',params[1])
    params = params[1]
    outputVal = params
    if params == None:
        return None
    params = params.lower()
    xCoord = None
    yCoord = None
    
    commaTest = params.split(",")
    if len(commaTest) > 1:
        xCoord = commaTest[0]
        yCoord = commaTest[1]
        if xCoord.isalpha() and yCoord.isnumeric(): # 
            if len(xCoord) == 1: # singular character
                convertedNum = ord(xCoord) - 96
                if convertedNum > 0 and convertedNum <= 26:
                    outputVal = str(convertedNum)+","+str(yCoord)
                    return outputVal
        else:
            if xCoord.isnumeric() and yCoord.isnumeric():
                outputVal = str(xCoord) +"-"+ str(yCoord) # direct conversion
                return outputVal
            else:
                print("invalid coordinates")
                pass
    else: # no comma, pretty much has to be alphanumeric because watch
        firstChar = params[0]
        if firstChar.isalpha():
            xCoord = firstChar
            yCoord = params[1:]
            if len(xCoord) == 1 and yCoord.isnumeric(): # singular character
                convertedNum = ord(xCoord) - 96
                if convertedNum > 0 and convertedNum <= 26:
                    outputVal = str(convertedNum)+","+str(yCoord)
                    return outputVal
        else:
            print("invalid coordinate format",params)
            pass
    #print("invalid Coords",params)    
    return None
    

def outputCommandQueue(commandQue):
    #print("OUT=>", commandQue)
    with open(SETTINGS['filename'], 'w') as outfile:
        #print("opened file")
        jsonMessage = json.dumps(commandQue)
        log("Writing commands: "+" - " +jsonMessage) # remove this?
        outfile.write(jsonMessage)

def addToQue(commands, handleCommand):
    #print("called add to que",commands,handleCommand)
    # adds to the already existing command que

    # log(commands)
    # Check if exists first
    # log("addQWue",commands)

    if not os.path.exists(SETTINGS['filename']):
        f = open(SETTINGS['filename'], "a")
        # make blank
        f.write('[]')
        f.close()

    with open(SETTINGS['filename'], 'r') as inFile:

        currentQue = json.load(inFile)
        #print("Current Queue:",currentQue,"\n adding:",commands)

        # if empty? or check len too
        if currentQue == None: 

            # Create empty list
            currentQue = []
            currentQue.extend(commands)
        else:
            currentQue.extend(commands)

        # determines if the command should be handled or not
        # unless this is being run from/after an internal command
        # has executed, leave as default (True)
        if handleCommand == True:
            # TODO: get callback on success?
            commandHandler(currentQue)
        elif handleCommand == False:
            # print("Sending Queue=>", currentQue)
            outputCommandQueue(currentQue)

def commandHandler(commandQue):
    # command handler will take 2 copies of the queue
    commandList = copy.copy(commandQue) #copy is unecessary now
    if(len(commandList) > 0):
        #print("adding que commandList ",commandList)
        addToQue(commandList, False)


def logCommandError(e, command):
    # print error
    print(e)
    # generate new log command
    command['type'] = "log"
    command['params'] = str(e)
    commandQue = []
    commandQue.extend(toJson(command))
    # add log to queue (to send error msg to SM)
    #print("logging command error")
    addToQue(commandQue, False)

    
def generateCommand(command,parameter,cmdData): #Generates command dictionary
    #print("generate",parameter,cmdData)
    command =  {'id': cmdData['id'], 'type':command, 'params':parameter, 'username': cmdData['author'], 
                'sponsor': cmdData['sponsor'], 'userid': cmdData['userid'], 'amount': cmdData['amount']}
    # print("Generated command:",command)
    return command

def validatePayment(command,price,message):
    # Validate payment data for the specified command
    # not necessary, just need price and message
    if command != None: 
        if SETTINGS['allFree'] or (SETTINGS['sponsorFree'] and message['sponsor']) or ((SETTINGS['fixedCost'] >0 and message['amount'] >= SETTINGS['fixedCost']) or message['amount'] >= price) :
           return True
        elif message['amount'] < price:
            print("Insuficcient payment",message['amount'],price)
            return False
        else:
            log("Payment Failed")
            return False
         
def validateCommand(parameters,userid,joinedChatters,simSettings,simData): 
    
    # {command is a array of parameters}
    comType = str(parameters[0])
    index = None
    price = None
    errorType = None
    #print("validating",parameters)
    # if comType == None or index error then wth??
    # Check if command valid first
    #print("Validating",comType,SETTINGS['commands'][comType]) #price
    if comType in SETTINGS['commands']: 
        # Setting validation
        if comType == "explode":
            if simSettings['allow_explode'] == False:
                errorType = "exploding is disabled"
                return False,index,errorType
            else:
                price =  SETTINGS['commands'][comType]
                return comType,index,price
        elif comType == "goto":
            if simSettings['allow_move'] == False:
                print('allowmove/?')
                errorType = "Moving is disabled"
                return False,index,errorType
            else:
                price =  SETTINGS['commands'][comType]
                return comType,index,price
        elif comType == "logout": # can condence these...
            if simSettings['enable_logout'] == False:
                errorType = "logging out is disabled"
                return False,index,errorType
            else:
                price =  SETTINGS['commands'][comType]
                return comType,index,price
        elif comType == "login": # can condence these... # TODO: diferenciate between spawn and login (allow others to spawn random things)
            if simSettings['allow_spawn'] == False:
                errorType = "logging in is disabled"
                return False,index,errorType
            if joinedChatters and userid in joinedChatters:
                    errorType = "User already in game"
                    return False,index,errorType
            else:
                price =  SETTINGS['commands'][comType]
                #print('valid',comType,price)
                return comType,index,price



        if len(parameters) == 1 or comType in SETTINGS['single']:
            price = SETTINGS['commands'][comType]
            #if an actual price
            if type(price) is int: 
                return comType,index,price
            # the command is supposed to have a parameter
            else: 
                errorType = "Invalid parameter count"
                return False,index,errorType

        # command = with X parameters (max params is infinite for now)
        elif len(parameters) > 1: 

            # grab the next index
            index = str(parameters[1])  # TODO: phase this wwhole var out eventually
           
            if comType == "spawn" : # only spawn one character if spawn command (must be woc)
                if simSettings['allow_spawn'] == False:
                    errorType = "Spawning is disabled"
                    return False,index,errorType
                if joinedChatters and userid in joinedChatters:
                    errorType = "User already in game"
                    return False,index,errorType
                # If valid item within that command
                if index in SETTINGS['commands'][comType]: # should just be for spawn
                    price =  SETTINGS['commands'][comType][index] 
                    return comType,index,price # IND
                else: #not spawn or no joined chatters
                    errorType = "Unrecognized unit"
            else: #not spawn just allow through because usernames (username validate here?)
                price =  SETTINGS['commands'][comType]
                return comType,index,price
        else:
            # TODO: just default to seraph for commands with no params
            errorType = "Param Invalid"
            print("Too many or not enough parameters",parameters)
    else:
        errorType = "Command Invalid"
    #  Eventually have output error message
    return False,index,errorType

def parseMessage(chat,mesID,joinedChatters,simSettings,simData):
    # parse any messages
    comType = None
    parameter = None
    parsed = {'id': mesID, 'command': chat.message, 'author': chat.author.name, 'sponsor': chat.author.isChatSponsor, 'userid': chat.author.channelId, 'amount': chat.amountValue, 'timestamp': chat.timestamp}
    #print("Parsed Message",parsed)
    #print(chat)
    message = parsed['command'].lower()

    # is actually a command # Possibly separate out to parsing function
    if message[0] in SETTINGS['prefix']: 
        #print("Found parametyer,",message)
        rawCommand = message.strip(message[0])
        parameters = rawCommand.split() #TODO: More validation to fix any potential mistakes
        #print("raw stuff",rawCommand)
        
        if len(parameters) == 0:
            log("Only Recieved Prefix")
            return None
        # because I don't plan to have multi command params stuff yet, I'm going to consider every word after is a single param
        username_param = " ".join(parameters[1:])

        comType,parameter,price = validateCommand(parameters,parsed['userid'],joinedChatters,simSettings,simData)
        if comType == False:
            # possibly use index for details?
            print("Received Error for",rawCommand+": ",price) 
        else:
            # Now validate any payments
            validPayment = validatePayment(comType,price,parsed)
            if validPayment:
                if comType != 'spawn' and comType != 'login': # check if command isnt a spawn command, because you will need a unit in game in order to participate (for now)
                    if joinedChatters and parsed['userid'] in joinedChatters:
                        if comType == "goto":
                            newParam = translateCoordinates(parameters)
                            if newParam:
                                parsed['params'] = newParam
                                username_param = newParam
                            else:
                                #print("Invalid coordinates")
                                return None
                        #print("sending",parsed,newParam)
                        command = generateCommand(comType,username_param,parsed)
                        return command  
                else: # if it is a spawn, parameter is the woc
                    if not joinedChatters or (joinedChatters and parsed['userid'] not in joinedChatters): #double check?(should alread fail validation)                        
                        command = generateCommand(comType,parameter,parsed)
                        return command
            else:
                log("Invalid Payment")
    # all other chats get checked for a logged in user (command)
    else:
        if joinedChatters and parsed['userid'] in joinedChatters:
            return generateCommand("chat",str(chat.message),parsed)
        else:
            log("User not loaded: " + str(parsed['author']))# can remove


    return None
    

def readChat():
    joinedChatters = [] # list of userIDs of chatters that spawned themselves into game, unfortunately do not have way to remove them yet
    commandQue = []
    simSettings = [] # global settings for simulation
    cID = 0
    errorTimeout = 0
    tryAgainTime = 0.5
    while chat.is_alive():
        # Also do stats reading/outputting
        
            # Scrap mechanic will be responsible for updating this list for every spawn and death.

        for c in chat.get().sync_items():
            #print("chat get",commandQue)
            #log(c.datetime+" - " +c.author.name+" - " +c.message)
            with open(chatterData, 'r') as inFile: # Can remove this and get chatter data from simulationData.ci.c
                joinedChatters = json.load(inFile)
            with open(simulationSettings, 'r') as sinFile: #might be causing bottleneck
                simSettings = json.load(sinFile) #TODO: try to reduce file reads
            with open(simulationData, 'r') as dinFile: #might be causing bottleneck
                simData = json.load(dinFile) #TODO: try to reduce file reads
            
            command = parseMessage(c,cID,joinedChatters,simSettings,simData)
            if command != None:
                #print("adding to ccq",command)
                print() # new line it
                commandQue.append(command)
                cID +=1
            if len(commandQue) >0:
                #print("adding to q >0",commandQue)
                addToQue(commandQue, True)
                if chat.is_replay():
                    commandQue = []
                    #print("Replay resetting que",commandQue)
            time.sleep(0.2)

        commandQue = []
        #print("reset que2",commandQue)

        try:
            #print('try rais status')
            chat.raise_for_status()
        except Exception as e:
            print("Got chat exception",type(e), str(e))
            break
            #chat = pytchat.create(SETTINGS['videoID']) # just uses default settings
    print("while loop broke out")
    return False



commandList = '''
List of available commands:

1. clear-cache
   > clears cached imports
2. reset-deaths
   > resets the death counter
3. help
   > displays this wonderful help message
'''
# 3. remove-mod
#   > restores the original game files, clears the cache, and removes the deathcounter and other files

def internalConsoleCommand(command):
    if(command == "clear-cache"): #TODO: Clear out entire folders of both source and destination
        shutil.rmtree(blueprintBase)
        os.makedirs(blueprintBase)
        log("import cache cleared")
    elif(command == "remove-mod"):
        print(commandList)
    elif(command == "help"):
        print(commandList)
    else:
        print("Unknown command, try typing 'help'")

def toJson(obj):
    # this is basically the same as generateCommand, but I made another one for some reason
    jsonContent = jsonContent = "[ {\"id\": "+str(obj["id"])+", \"type\": \""+str(obj["type"])+"\", \"params\": \""+str(obj["params"])+"\", \"username\": \""+str(obj["username"])+"\", \"sponsor\": "+str(obj["sponsor"]).lower()+", \"userid\": \""+str(obj["userid"])+"\", \"amount\": "+str(obj["amount"])+"} ]"
    # specical configuration if more than one parameter
    if not isinstance(obj['params'], str):
        params =  "\""+"\",\"".join(obj["params"])+"\""
        jsonContent = "[ {\"id\": "+str(obj["id"])+", \"type\": \""+str(obj["type"])+"\", \"params\": [ "+params+" ], \"username\": \""+str(obj["username"])+"\", \"sponsor\": "+str(obj["sponsor"]).lower()+", \"userid\": \""+str(obj["userid"])+"\", \"amount\": "+str(obj["amount"])+"} ]"
    return json.loads(jsonContent)

# Planned commands: give speed, give slowness, lightning strike?, chop wood?
# chat = pytchat.create(video_id =  SETTINGS['videoID']) # start reading livechat #Create it here?? or store in settings and generate on main()

# custom logging style (kinda dumb ngl)
def log(string):
    print("["+str(string)+"]")

if __name__ == '__main__':
    if debug:
        pass
        # debug stuff here
    else:

        # verify working video url
        try:
            print("tryfirst")
            try:
                print("try second")
                chat = pytchat.create(video_id=sys.argv[1]) # dumb way to do this but okay
                SETTINGS['videoID'] = sys.argv[1]
            except:
                chat = pytchat.create(SETTINGS['videoID']) #-- DEFAULT STREAM
                #chat = pytchat.create(video_id="FPoX_M7zAYA") # Live test stream
                #chat = pytchat.create(video_id="53SDDytPAzI") # Old stream chat test
                #chat = pytchat.create(video_id="2foo8cmrXjs") # Old stream chat test (Longer and more commands)
                #chat = pytchat.create(video_id="6s5COaPWNt8") # Most updated stream (long)
        except:
            log("Video Id Failure")
            ValidVideo = False
            userIn = ''
            while(not ValidVideo):
                if len(userIn) > 0:
                    log('Video Id \'{0}\' is not valid'.format(userIn))
                try:
                    userIn = input("YouTube Video Id => ")
                    chat = pytchat.create(video_id=userIn)
                    SETTINGS['videoID'] = userIn
                    ValidVideo = True
                except:
                    print("idk wtf this is for")
                    pass
        # print("Checking for backups...") maybe sum day :(

        # create nessesary files and folders if the do not exist
        if not os.path.exists(dataBase):
            os.makedirs(dataBase)



        streamchatFile = open(os.path.join(dataBase, "streamchat.json"), "w")
        streamchatFile.write("[]")
        streamchatFile.close()
        
        # install modded lua files
        #copyfile(os.path.join(base,"survival_streamreader.lua"), os.path.join(dataBase, "survival_streamreader.lua"))
        #copyfile(os.path.join(base,"BaseWorld.lua"), os.path.join(smBase, "worlds", "BaseWorld.lua"))
        #copyfile(os.path.join(base,"SurvivalGame.lua"), os.path.join(smBase, "SurvivalGame.lua"))

        log("Stream Reader initialized")
        print("running reader")
        errorTimeout = 0
        while errorTimeout <= 10: # 10 retries before stopping
            print("Trying read chat")
            #try:
            result = readChat()
            errorTimeout = 0
            if result == False:
                print("readchat got error",result)
                chat = pytchat.create(SETTINGS['videoID']) #-- DEFAULT STREAM 
            #except Exception as e:
            #print("Read Chat failure, trying again?",type(e), str(e),errorTimeout)
            errorTimeout += 1
            time.sleep(3) # sleep 4 seconds and try again
        print("try readChat start broke out")

                
