# Terminate a program (currently used for errors)
import sys
import os.path
from math import *

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
def stop(Message = ""):
    sys.exit(Message)

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
def wait(Message = ""):    
    raw_input(Message)
    
    
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
def NicePrint(NiceDict,Message=""):
    if len(Message) > 0:
        print("\n"+Message)
    for key in NiceDict:
        if len(Message) > 0:
            print("  "),
        print(str(key)+" -> "+str(NiceDict[key]))         
    print("")
 

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# Folder:      Folder where the file should be
# FileName:    Filname of the file to check   
# Message:     Message to be shown
# ShowMessage: ShowMessages if there is an error or even if not
# ErrorExit:   Exit the whole program if file could not be found or only return False

def FileExistCheck(Folder,FileName,Message="",ShowMessage=False,ErrorExit=True):
    if (len(Message) > 0):
        ShowMessage = True
    
    if (os.path.isfile(Folder+FileName) == False):
        if ShowMessage | ErrorExit:
            print(Message+"The file '"+FileName+"' in the folder '"+Folder+"' is missing! Excecution stopped!!!")
        if ErrorExit:
            sys.exit()
        else:
            return False
    else:
        if ShowMessage:        
            print(Message+""+"The file '"+FileName+"' in the folder '"+Folder+"' is OK.")
        return True
            
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
def IsFloatNumber(Number):
    try:
        float(Number)
        return True
    except ValueError:
        return False   
    
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
def IsIntNumber(Number):
    try:
        int(Number)
        return True
    except ValueError:
        return False        

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #     
def StripToNumber(Text,ThrowError=False,Message=""):
    if IsFloatNumber(Text):
        if IsIntNumber(Text):
            #print "Integer"
            return int(Text)
        else:
            #print "Float"
            return float(Text)
    else:
        #print "Text"
        if ThrowError:
            stop(Message+"One of the entered elements is not a number but it has to be a number:"+Text)
        else:
            return Text
    
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #     
def GetTabSeperatedLigne(Ligne):
    return Ligne.split("\t")
       
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #    

class TDimensions():
    def __init__(self):
        self.xMin = float('inf')
        self.xMax = -float('inf')    

        self.yMin = float('inf')
        self.yMax = -float('inf')
        
    def Add(self,x,y):
        self.xMin = min(x,self.xMin)
        self.xMax = max(x,self.xMax)

        self.yMin = min(y,self.yMin)
        self.yMax = max(y,self.yMax)             

    def GetDimensions(self):
        return [self.xMin,self.xMax,self.yMin,self.yMax]
    
    def Width(self):
        return (self.xMax-self.xMin)
    
    def Height(self):
        return (self.yMax-self.yMin)    
    
    def __str__(self):
        return str([self.xMin,self.xMax,self.yMin,self.yMax])
    
    
    
    
def Haversine_Distance(lon1, lat1, lon2, lat2):
    # convert decimal degrees to radians 
    lon1, lat1, lon2, lat2 = map(radians, [lon1, lat1, lon2, lat2])
    # Haversine_Distance formula 
    dlon = lon2 - lon1 
    dlat = lat2 - lat1 
    a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
    c = 2 * asin(sqrt(a)) 
    return float(1000*6371 * c)      
    
    
    
    
    
    
    
    
    
    
    