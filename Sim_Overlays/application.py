import os, math
from flask import Flask, render_template, url_for, g
from jinja2 import Environment, PackageLoader, select_autoescape
import re
import json
from flask_socketio import SocketIO
import time
import asyncio
import sharedData
SIMULATION_DATA = None
ALLOWED_EXTENSIONS = set(['txt', 'pdf', 'png', 'jpg', 'jpeg', 'gif'])
app = Flask(__name__)
app.config['SECRET_KEY'] = 'SUPERSECRETSKELINGTON'
socketio = SocketIO(app)


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

@socketio.on('getData')
def handle_get_json(data, methods=['GET', 'POST']): # enmits out current simulation data when recieve event
   print("got handle jason")
   global SIMULATION_DATA
   socketio.emit('simData', SIMULATION_DATA)

@socketio.on('dataPacket') # recieves and setsvdata TODO: also possibly reduce byte transfer by just emitting changeEvent and having this read the change
def handle_incoming_dataPacket(data, methods=['GET', 'POST']):
    global SIMULATION_DATA
    SIMULATION_DATA = data
    #print("recieved sim data")
    socketio.emit('simData', SIMULATION_DATA)

@socketio.on('dataFlag') # Recieves command that data changed and reads new data from file directly
def handle_data_changed(jsonData, methods=['GET', 'POST']): #opens json data file
    global SIMULATION_DATA
    jsonDataFile = open("../JsonData/SimOutput/simulationOutput.json","r")
    print(jsonDataFile,"datafile?")
    SIMULATION_DATA = json.load(jsonDataFile)
    socketio.emit('simData', SIMULATION_DATA)

#_______________________________ SMARL Overlay CODE _________________________________________

@app.route('/', methods=['GET','POST']) #Showsall possible overlays for quick picking
def index():
    return render_template('simulation_map.html',SimData=SIMULATION_DATA, properties=sharedData._Properties)

@app.route('/simulation_map', methods=['GET','POST']) # Displays Race Information (Track, nracer...)
def smarl_intro_board():
    return render_template('simulation_map.html',SimData=SIMULATION_DATA, properties=sharedData._Properties)

@app.route('/smarl_get_realtime_data', methods=['GET','POST']) # Displays Race Results
def smarl_get_lapData(): #Get lap data
    print("REturning",SIMULATION_DATA)
    return json.dumps(SIMULATION_DATA)



@app.context_processor
def test_debug():

    def console_log(input_1,  input_2 = '', input_3 = ''):
        print("logging", input_1)
        print(input_2)
        print(input_3)
        return input_1

    return dict(log=console_log)


def main(): 
    sharedData.init()
    print("sruning??")
    if '__main__' == __name__:
        socketio.run(app, debug=True,use_reloader=True)
    
main()

# -------------------------------------------

    
    
