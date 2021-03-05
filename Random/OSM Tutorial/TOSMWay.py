class TOSMWay(object):

    def __init__(self, idWay):
        
        self.idWay    = idWay
        self.NodeList = []
        
        
        self.Length = None
        self.HighWayType    = None
        self.MaxSpeed       = None
        self.Lanes          = None
        self.OneWay             = False
        
        
        
    def AddNode(self,idNode):
        self.NodeList.append(idNode)
        
    def NumberOfNodes(self):
        return len(self.NodeList)
    
    def Print(self):
        print self.idWay,'->',self.NodeList