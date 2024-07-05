from urllib import response
import requests
from requests.exceptions import HTTPError

_Properties = { # various global properties
    "transition_short": 500,
    "transition_shorter": 250,
    "transition_long": 1000,
    "transition_longer": 1300
}
#// replace trrans line: find: .duration(####) replace: .duration("{{properties.transition_longer}}")
# find: yScale(Number(d['id'])) replace: yScale(i + 1) (dont forget to add i to previous function if not there)
#print("sharedData",_SpecificRaceData)
SMARL_API_URL = "http://seraphhosts.ddns.net:8080/api" # TODO: change this to simulation api? or use same api but dif endpoints?
SMARL_LOCAL_URL = "http://192.168.1.250:8080/api"
IS_LOCAL = False # Remember to change this when you should, Maybe automate this??

def get_smarl_url(): # returns smarl url based on is_local
    if IS_LOCAL: return SMARL_LOCAL_URL
    else: return SMARL_API_URL


def setSimData(data):
    print("setting racer Data")
    global SIMULATION_DATA
    SIMULATION_DATA = data # or append?
    print(SIMULATION_DATA)

def getSimData(): # TODO: alter to grab simulation data
    print("Getting racer data")
    sim_data = None
    try:
        response = requests.get(get_smarl_url() + "/get_racers_in_season") # in league i
        #response = requests.get(get_smarl_url() + "/get_racers_in_league")
        response.raise_for_status()
        # access JSOn content
        
        jsonResponse = response.json()
      
        #print("got racers",all_racers)
    except HTTPError as http_err:
        print(f'HTTP error occurred: {http_err}')
    except Exception as err:
        print(f'GRacerdata Other error occurred: {err}')        # compile owners into racers
    filtered_racers =  [d for d in jsonResponse if int(d['league_id']) == _SpecificRaceData['league_id']] # filter for league
    print("\n\nfiltered racers = ",len(filtered_racers),_SpecificRaceData['league_id'],"\n",filtered_racers)
    all_racers = filtered_racers
    return all_racers


def uploadSimUpdate(race_id,resultBody): # store simulation grid into db TODO: finish
    resultData = None
    resultJson = {"race_id":race_id, "data":resultBody}
    print("uploading results",race_id,resultBody,resultJson)
    #pass #TODO: REMOVE THIS when ready for official race?
    try:
        response = requests.post(get_smarl_url() + "/update_race_qualifying",json=resultJson )
        response.raise_for_status()
        # access JSOn content
        jsonResponse = response.json()
        print("Entire JSON response")
        print(jsonResponse)
        all_racers = jsonResponse
    except HTTPError as http_err:
        print(f'HTTP error occurred: {http_err}')
        return False
    except Exception as err:
        print(f'Other error occurred: {err}')        # compile owners into racers
        return False
    return True


def updateSimData(): # gets new pull of racer data from database
    global SIMULATION_DATA
    SIMULATION_DATA = getSimData()

def init():
    global SIMULATION_DATA
    #SIMULATION_DATA = getSimData()

init()
