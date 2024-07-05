Timer2 = class( nil ) -- TImer 2.0

function Timer2.start( self, ticks )
	self.ticks = ticks or 0
	self.count = 0
end

function Timer2.reset( self )
	self.ticks = self.ticks or -1
	self.count = 0
end

function Timer.stop( self )
	self.ticks = -1
	self.count = 0
end

function Timer2.tick( self )
	self.count = self.count + 1
end

function Timer2.status(self)
	return self.count 
end

function Timer2.remaining(self)
	return self.ticks-self.count
end

function Timer2.done( self )
	return self.ticks >= 0 and self.count >= self.ticks
end
