class TOSMNode(object):

    def __init__(self, idNode, Lat = None, Lon = None):
        
        self.idNode = idNode
        self.Lat    = Lat
        self.Lon    = Lon
        
    
        self.EndPosition    = None
        self.MiddlePosition = None
        self.ContainedInWay = []
        
    def Print(self):
        print self.idNode,'->',[self.EndPosition,self.MiddlePosition]