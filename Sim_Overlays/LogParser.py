import os, math, sys
import logging
import json
import socketio
import time
import datetime
#import gspread
#import watcher, asyncio
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

logging.basicConfig(level=logging.INFO,
                        format='%(asctime)s - %(message)s',
                        datefmt='%Y-%m-%d %H:%M:%S')
#max_http_buffer_size – The maximum size of a message when using the polling transport. The default is 1,000,000 bytes.
sio = socketio.Client()
TCP_CONNECTED = False
DUPECOUNT = 0

def get_time_from_seconds(seconds):
    minutes = "{:02.0f}".format(math.floor(seconds/60))
    seconds = "{:06.3f}".format(seconds%60)
    timeStr  = minutes + ":" +seconds
    return timeStr

def get_seconds_from_time(time):
    minutes = time[0:2]
    seconds = time[3:5]
    milis = time[7:11]
    newTime = (int(minutes)*60) + int(seconds) + (int(milis)/1000)
    return newTime

# SOCKET STUF #Async may be better?
 
@sio.event
def connect():
    global TCP_CONNECTED
    print("TCP Connected")
    TCP_CONNECTED = True

@sio.event
def connect_error():
    global TCP_CONNECTED
    print("TCP connection failed")
    TCP_CONNECTED = False
    retryConnection()

@sio.event
def disconnect():
    global TCP_CONNECTED
    print("TCP Disconnected")
    TCP_CONNECTED = False
    #retryConnection()
           
def retryConnection():
    print("retrying connection")
    sio.connect('http://localhost:5000')


# main frame=============
def findLogFile():
    max_mtime = 0
    max_file = ""
    for dirname,subdirs,files in os.walk("../JsonData/SimOutput/"):
        for fname in files:
            full_path = os.path.join(dirname, fname)
            mtime = os.stat(full_path).st_mtime
            if fname == 'simulationOutput.json':
                print("found file")
                max_mtime = mtime
                max_dir = dirname
                max_file = fname
    return max_file

def sortByKeys(keys,lis): #keys is a list of keys #mailny for points so reverse is true
    newList =sorted(lis, key = lambda i: (i[keys[0]], i[keys[1]], i[keys[2]], i[keys[3]], i[keys[4]]),reverse=True ) 
    return newList

def sortByKey(key,lis): #just sorts list by one key #mainly for pos so reverse is false
    newList =sorted(lis, key = lambda i: i[key] )
    return newList

def getIndexByKey(key,lis):
    #print('getting index',key,lis)
    newIndex = next((index for (index, d) in enumerate(lis) if d['ID'] == key), None)
    return newIndex
    
def getTimefromTimeStr(timeStr):
    minutes = int(timeStr[0:2])
    seconds = int(timeStr[3:5])
    milliseconds = int(timeStr[6:9])
    myTime = datetime.datetime(2019,7,12,1,minutes,seconds,milliseconds)
    return myTime

def readFile(fileName):
    data = None
    logRead = False
    while logRead == False:
        try:
            with open(fileName,'r') as file:
            #file = open(fileName,'r')
                data = json.load(file)
                #print('read?',sys.getsizeof(data))
                logRead = True
        except Exception as e:
            pass    
            #print("Log Read Miss",type(e), str(e)) #happens quite a bit
        
    if not data: # If no new data seems to be added
            #print("no data")
            logRead = True
    else: # If data is added
        #print("got data",data)
        outputData(data)   

# Readfile handler
class ReadFileHandler(FileSystemEventHandler):
    # super annoying but hard coding file finding 
    # TODO: figure out how to pass param to event handler
    fileDir = '../JsonData/SimOutput/'
    logFile = 'simulationOutput.json'
    fileName = fileDir+logFile
    lastDupeCount = DUPECOUNT
    def __init__(self):
        self.lastDupeCount = DUPECOUNT

    def on_modified(self, event):
        if DUPECOUNT != self.lastDupeCount: 
            #print(f'event type: {event.event_type}  path : {event.src_path}')
            # filter so only one event?
            readFile(fileName)
            self.lastDupeCount = DUPECOUNT # prevent dup



def outputData(data):  #Directly output data to flask server via tcp
    size = sys.getsizeof(data)
    #print("outputting data:",size)
    pass
    if not TCP_CONNECTED :
        #print("Did not send packet (not connected)")
        return 
    if size > 0:
        sio.emit('dataPacket', data) # size might be too big
        #print("Sent data packet",size)
    return size

if __name__ == "__main__":
    print("starting Reader")
    try:
        sio.connect('http://localhost:5000') # might need diff port
    except:
        print("connection failed, but its okay")

    logFile = findLogFile()
    fileDir = '../JsonData/SimOutput/'
    fileName = fileDir+logFile
    print("watching",fileName)
    callback = lambda *a: readFile(fileName)
    
    event_handler = ReadFileHandler()
    observer = Observer()
    #observer.event_queue.maxsize = 1
    observer.schedule(event_handler, fileDir, recursive=False)
    observer.start()
    #print(observer.event_queue.maxsize)
    try:
        while observer.is_alive():
            DUPECOUNT += 0.1
            observer.join(0.4) # TIMEOUT DELAY ()
    finally:
        observer.stop()
        observer.join()
        
    print("stoped running")
    
#main()

# -------------------------------------------

    
    